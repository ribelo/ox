module L = Ox_observability.Logger
module O = Ox_otel

let check_string = Alcotest.(check string)
let check_int = Alcotest.(check int)
let json raw = Yojson.Safe.from_string raw
let member name = Yojson.Safe.Util.member name
let list json = Yojson.Safe.Util.to_list json
let string json = Yojson.Safe.Util.to_string json
let first name document = document |> member name |> list |> List.hd

let contains haystack needle =
  let rec search index =
    index + String.length needle <= String.length haystack
    && (String.sub haystack index (String.length needle) = needle || search (index + 1))
  in
  String.length needle = 0 || search 0

(* One collector request: the target, its header lines, and the decoded OTLP body. *)
type request = { target : string; headers : (string * string) list; body : Yojson.Safe.t }

let header headers name =
  let name = String.lowercase_ascii name in
  List.find_map
    (fun (key, value) ->
      if String.equal (String.lowercase_ascii key) name then Some value else None)
    headers

let string_attr attrs key =
  match List.find_opt (fun attr -> attr |> member "key" |> string = key) attrs with
  | Some attr -> attr |> member "value" |> member "stringValue" |> string
  | None -> "<absent>"

let log_records received =
  List.concat_map
    (fun request ->
      if contains request.target "/v1/logs" then
        request.body |> first "resourceLogs" |> first "scopeLogs" |> member "logRecords"
        |> list
      else [])
    received

(* Every OTLP metric row the collector received, in arrival order. *)
let metric_rows received =
  List.concat_map
    (fun request ->
      if contains request.target "/v1/metrics" then
        request.body |> first "resourceMetrics" |> first "scopeMetrics"
        |> member "metrics" |> list
      else [])
    received

let metric_row name received =
  List.find_opt (fun row -> row |> member "name" |> string = name) (metric_rows received)

let metric_named name received =
  match metric_row name received with
  | Some row -> row
  | None -> Alcotest.failf "no metric named %s on the wire" name

let data_point metric field =
  metric |> member field |> member "dataPoints" |> list |> List.hd

let wire_encoding () =
  (* ^notel-z7dk: v1 OTLP resource/scope/span envelope and decimal ns strings. *)
  let span : O.Otlp_json.span =
    {
      trace_id = "0123456789abcdef0123456789abcdef";
      span_id = "0123456789abcdef";
      parent_span_id = Some "1122334455667788";
      name = "nema.query";
      start_unix_ns = 1_723_000_000_000_000_000L;
      end_unix_ns = 1_723_000_000_100_000_000L;
      attrs = [ ("db.system", "ladybug") ];
      status_code = 2;
      status_message = "failed";
    }
  in
  let doc =
    O.Otlp_json.encode_traces_request
      ~resource_attrs:[ ("service.name", "nema") ]
      ~scope_name:"ox_otel" [ span ]
    |> json
  in
  let resource = first "resourceSpans" doc in
  let attrs = resource |> member "resource" |> member "attributes" |> list in
  check_string "service identity" "nema"
    (List.hd attrs |> member "value" |> member "stringValue" |> string);
  let scope = first "scopeSpans" resource in
  let encoded = first "spans" scope in
  check_string "trace ID" span.trace_id (encoded |> member "traceId" |> string);
  check_string "parent ID" "1122334455667788" (encoded |> member "parentSpanId" |> string);
  check_string "nanoseconds are decimal JSON strings" "1723000000100000000"
    (encoded |> member "endTimeUnixNano" |> string);
  check_int "error code" 2
    (encoded |> member "status" |> member "code" |> Yojson.Safe.Util.to_int);
  let record : L.record =
    {
      ts = 1_723_000_000.;
      level = Warn;
      service = "nema";
      msg = "degraded";
      fields = [ ("retry", Int 3); ("secret", String "<redacted>") ];
      context = [ ("trace_id", span.trace_id); ("span_id", span.span_id) ];
    }
  in
  let doc =
    O.Otlp_json.encode_logs_request ~resource_attrs:[] ~scope_name:"ox_otel" [ record ]
    |> json
  in
  let row = doc |> first "resourceLogs" |> first "scopeLogs" |> first "logRecords" in
  check_int "WARN number" 13 (row |> member "severityNumber" |> Yojson.Safe.Util.to_int);
  check_string "log trace" span.trace_id (row |> member "traceId" |> string);
  check_string "message" "degraded"
    (row |> member "body" |> member "stringValue" |> string);
  let attrs = row |> member "attributes" |> list in
  let retry = List.find (fun attr -> attr |> member "key" |> string = "retry") attrs in
  check_string "integer attribute encoded as OTLP intValue" "3"
    (retry |> member "value" |> member "intValue" |> string)

(* A measurement exactly as the exporter records it, so the wire tests can bypass the
   instruments and assert the encoder boundary itself. *)
let metric ?(description = "") ?(unit_ = "") ?(attrs = []) ?(ts_ms = 1_000) ~name ~kind
    value : O.Meter.point =
  { name; description; unit_; attrs; kind; value; ts_ms }

let encode_metrics ?(resource_attrs = [ ("service.name", "nema") ]) points =
  let rows = O.Metric_aggregation.aggregate_points points in
  O.Otlp_json.encode_metrics_request ~resource_attrs ~scope_name:"ox_otel" rows |> json

let metrics_of body =
  body |> first "resourceMetrics" |> first "scopeMetrics" |> member "metrics" |> list

let metric_of name body =
  match
    List.find_opt (fun row -> row |> member "name" |> string = name) (metrics_of body)
  with
  | Some row -> row
  | None -> Alcotest.failf "no metric named %s in %s" name (Yojson.Safe.to_string body)

let attr attrs key =
  match List.find_opt (fun row -> row |> member "key" |> string = key) attrs with
  | Some row -> row |> member "value" |> member "stringValue" |> string
  | None -> "<absent>"

(* Copied from v1's metric assertions: an overflowing integer sum must leave the integer
   path, and a saturated timestamp must never render as a negative decimal. *)
let rec json_has_negative_as_int = function
  | `Assoc fields ->
      List.exists
        (function
          | "asInt", `String s -> String.length s > 0 && Char.equal s.[0] '-'
          | _, value -> json_has_negative_as_int value)
        fields
  | `List values -> List.exists json_has_negative_as_int values
  | _ -> false

let rec json_has_negative_time = function
  | `Assoc fields ->
      List.exists
        (function
          | ("timeUnixNano" | "startTimeUnixNano" | "observedTimeUnixNano"), `String s ->
              String.length s > 0 && Char.equal s.[0] '-'
          | _, value -> json_has_negative_time value)
        fields
  | `List values -> List.exists json_has_negative_time values
  | _ -> false

(* ^notel-bez2 ^notel-8ixo: v1's pure OTLP metric encoding kept — resource and scope
   envelopes, delta sums, bucket counts of bounds+1, decimal-string integers and
   timestamps, and the ProtoJSON spellings of the special doubles. *)
let metric_wire_encoding () =
  let counter = O.Meter.Counter { monotonic = true } in
  let up_down = O.Meter.Counter { monotonic = false } in
  let histogram = O.Meter.Histogram (O.Meter.histogram_config [ 10.0; 20.0 ]) in
  let body =
    encode_metrics
      [
        metric ~name:"http.requests" ~unit_:"{request}"
          ~attrs:[ ("route", "/query") ]
          ~kind:counter (Int 2);
        metric ~name:"http.requests" ~unit_:"{request}"
          ~attrs:[ ("route", "/query") ]
          ~kind:counter (Int 1);
        metric ~name:"queue.depth" ~kind:up_down (Int 5);
        metric ~name:"queue.depth" ~kind:up_down (Int (-7));
        metric ~name:"http.duration" ~unit_:"ms" ~kind:histogram (Float 5.0);
        metric ~name:"http.duration" ~unit_:"ms" ~kind:histogram (Float 15.0);
        metric ~name:"http.duration" ~unit_:"ms" ~kind:histogram (Float 25.0);
      ]
  in
  let resource =
    body |> first "resourceMetrics" |> member "resource" |> member "attributes" |> list
  in
  check_string "the resource identity" "nema" (attr resource "service.name");
  check_string "the scope" "ox_otel"
    (body |> first "resourceMetrics" |> first "scopeMetrics" |> member "scope"
   |> member "name" |> string);
  let requests = metric_of "http.requests" body in
  let sum = requests |> member "sum" in
  check_int "a counter is a delta sum" 1
    (sum |> member "aggregationTemporality" |> Yojson.Safe.Util.to_int);
  Alcotest.(check bool)
    "a counter is monotonic" true
    (sum |> member "isMonotonic" |> Yojson.Safe.Util.to_bool);
  let point = data_point requests "sum" in
  check_string "increments are summed" "3" (point |> member "asInt" |> string);
  check_string "the unit" "{request}" (requests |> member "unit" |> string);
  check_string "the series attributes" "/query"
    (attr (point |> member "attributes" |> list) "route");
  check_string "the window start is a decimal nanosecond string" "1000000000"
    (point |> member "startTimeUnixNano" |> string);
  let depth = metric_of "queue.depth" body |> member "sum" in
  check_int "an up-down counter is a delta sum too" 1
    (depth |> member "aggregationTemporality" |> Yojson.Safe.Util.to_int);
  Alcotest.(check bool)
    "and not monotonic" false
    (depth |> member "isMonotonic" |> Yojson.Safe.Util.to_bool);
  check_string "signed increments are summed" "-2"
    (data_point (metric_of "queue.depth" body) "sum" |> member "asInt" |> string);
  let durations = metric_of "http.duration" body in
  let histogram = durations |> member "histogram" in
  check_int "a histogram is a delta histogram" 1
    (histogram |> member "aggregationTemporality" |> Yojson.Safe.Util.to_int);
  let point = data_point durations "histogram" in
  check_string "count" "3" (point |> member "count" |> string);
  Alcotest.(check (float 0.001))
    "sum" 45.0
    (point |> member "sum" |> Yojson.Safe.Util.to_float);
  Alcotest.(check (list string))
    "one count per bucket, overflow last" [ "1"; "1"; "1" ]
    (point |> member "bucketCounts" |> list |> List.map string);
  Alcotest.(check (list (float 0.001)))
    "explicitBounds are configuration" [ 10.0; 20.0 ]
    (point |> member "explicitBounds" |> list |> List.map Yojson.Safe.Util.to_float);
  let overflow =
    encode_metrics
      [
        metric ~name:"wrap" ~kind:counter (Int (max_int - 1));
        metric ~name:"wrap" ~kind:counter (Int 3);
      ]
  in
  Alcotest.(check bool)
    "an integer sum that overflows leaves the integer path" false
    (json_has_negative_as_int overflow);
  let late =
    encode_metrics
      [ metric ~name:"late" ~kind:counter ~ts_ms:((max_int / 1_000_000) + 1) (Int 1) ]
  in
  Alcotest.(check bool)
    "a saturated timestamp never renders negative" false (json_has_negative_time late);
  let special = encode_metrics [ metric ~name:"special" ~kind:counter (Float nan) ] in
  check_string "NaN crosses the wire in its ProtoJSON spelling" "NaN"
    (data_point (metric_of "special" special) "sum" |> member "asDouble" |> string)

(* ^notel-bez2: the histogram's explicit bounds are validated where the instrument is
   built, and each instrument records the point its caller intended. *)
let instruments_stamp_points () =
  let seen = ref [] in
  let meter =
    O.Meter.create ~now_ms:(fun () -> 42) ~record:(fun p -> seen := p :: !seen)
  in
  let requests =
    O.Meter.counter meter ~name:"http.requests" ~unit_:"{request}" ~description:"served"
      ~attrs:[ ("route", "/query") ]
      ()
  in
  O.Meter.add requests 2.5;
  let durations = O.Meter.histogram meter ~boundaries:[ 10.0 ] ~name:"http.duration" () in
  O.Meter.record durations 7.0;
  let points = List.rev !seen in
  Alcotest.(check int) "one point per measurement" 2 (List.length points);
  let counter : O.Meter.point = List.nth points 0 in
  check_string "the counter's name" "http.requests" counter.name;
  check_string "its unit" "{request}" counter.unit_;
  check_string "its description" "served" counter.description;
  check_string "its attribute" "/query" (List.assoc "route" counter.attrs);
  Alcotest.(check bool)
    "a counter is monotonic" true
    (counter.kind = O.Meter.Counter { monotonic = true });
  Alcotest.(check bool) "recorded as a double" true (counter.value = O.Meter.Float 2.5);
  check_int "stamped by the meter's clock" 42 counter.ts_ms;
  let sample : O.Meter.point = List.nth points 1 in
  check_string "the histogram's name" "http.duration" sample.name;
  Alcotest.(check bool) "the sample value" true (sample.value = O.Meter.Float 7.0);
  Alcotest.(check bool)
    "the instrument's bounds" true
    (sample.kind = O.Meter.Histogram (O.Meter.histogram_config [ 10.0 ]));
  let reject bounds =
    match O.Meter.histogram meter ~boundaries:bounds ~name:"h" () with
    | exception Invalid_argument _ -> ()
    | _ ->
        Alcotest.failf "expected Invalid_argument for bounds %s"
          (String.concat ";" (List.map string_of_float bounds))
  in
  reject [ nan ];
  reject [ infinity ];
  reject [ neg_infinity ];
  reject [ 2.0; 1.0 ];
  reject [ 1.0; 1.0 ];
  reject [ 0.0; -0.0 ];
  Alcotest.(check (list (float 0.0)))
    "the empty bound list is valid" []
    (O.Meter.histogram_boundaries (O.Meter.histogram_config []));
  ignore (O.Meter.histogram meter ~boundaries:[ -1.0; 0.0; 1.0 ] ~name:"h" ());
  let durations = O.Meter.histogram meter ~boundaries:[] ~name:"h" () in
  (match O.Meter.add durations 1.0 with
  | exception Invalid_argument _ -> ()
  | () -> Alcotest.fail "a histogram records samples, not adds");
  match O.Meter.record requests 1.0 with
  | exception Invalid_argument _ -> ()
  | () -> Alcotest.fail "a counter adds increments, not records"

let with_collector ?(status = 200) ?(refuse_traces = false) f =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let listener =
            Eio.Net.listen ~sw ~backlog:8 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
          in
          let port =
            match Eio.Net.listening_addr listener with
            | `Tcp (_, port) -> port
            | _ -> assert false
          in
          let received = ref [] in
          Eio.Fiber.fork_daemon ~sw (fun () ->
              while true do
                let flow, _ = Eio.Net.accept ~sw listener in
                let input = Eio.Buf_read.of_flow ~max_size:262144 flow in
                let target = Eio.Buf_read.line input in
                let rec headers reversed length =
                  let line = Eio.Buf_read.line input in
                  if line = "" then (List.rev reversed, length)
                  else
                    let prefix = "content-length:" in
                    let lower = String.lowercase_ascii line in
                    let length =
                      if String.starts_with ~prefix lower then
                        int_of_string
                          (String.trim
                             (String.sub line (String.length prefix)
                                (String.length line - String.length prefix)))
                      else length
                    in
                    let header =
                      match String.index_opt line ':' with
                      | Some colon ->
                          ( String.sub line 0 colon,
                            String.trim
                              (String.sub line (colon + 1)
                                 (String.length line - colon - 1)) )
                      | None -> (line, "")
                    in
                    headers (header :: reversed) length
                in
                let headers, length = headers [] 0 in
                let body = Eio.Buf_read.take length input in
                received := { target; headers; body = json body } :: !received;
                Eio.Flow.copy_string
                  (* Real collectors (inn, the OTel collector) answer 200 with a JSON body
                     — {} or a partialSuccess — so the stub does too (^notel-6o5v). *)
                  (if
                     status = 200
                     && not (refuse_traces && contains target "POST /otlp/v1/traces ")
                   then
                     "HTTP/1.1 200 OK\r\n\
                      Content-Type: application/json\r\n\
                      Content-Length: 2\r\n\
                      \r\n\
                      {}"
                   else "HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\n\r\n")
                  flow
              done;
              `Stop_daemon);
          let client = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
          let endpoint = Printf.sprintf "http://127.0.0.1:%d/otlp" port in
          (* ^notel-1stb: a lifecycle defect shows up as a hang; the bound fails the test
             instead of blocking the suite. *)
          Eio.Time.with_timeout_exn env#clock 5. (fun () ->
              f env sw client endpoint received)))

let exporter_ok result =
  match result with
  | Ok x -> x
  | Error err -> Alcotest.failf "exporter error: %a" O.pp_error err

let log_and_spans () =
  (* ^notel-6m2q ^notel-j9vc ^notel-p4xe ^pcaps-wury: one logger, two signal endpoints,
     nested spans, correlated logs, explicit drain before borrowed client release. *)
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~span_ids:(O.span_ids exporter) ~reporter:(O.reporter exporter) ()
      in
      ignore
        (L.span logger "outer" (fun () ->
             L.info logger "query started";
             ignore (L.span logger "inner" (fun () -> Ok ()) : (unit, string) result);
             Ok ())
          : (unit, string) result);
      exporter_ok (O.flush exporter);
      exporter_ok (O.shutdown exporter);
      exporter_ok (O.shutdown exporter);
      check_int "one log batch and one traces batch" 2 (List.length !received);
      let paths = List.map (fun request -> request.target) !received in
      Alcotest.(check bool)
        "logs endpoint" true
        (List.exists
           (fun path -> String.ends_with ~suffix:"/otlp/v1/logs HTTP/1.1" path)
           paths);
      let spans =
        List.concat_map
          (fun request ->
            if String.starts_with ~prefix:"POST /otlp/v1/traces " request.target then
              let scope = request.body |> first "resourceSpans" |> first "scopeSpans" in
              scope |> member "spans" |> list
            else [])
          !received
      in
      check_int "two completed spans" 2 (List.length spans);
      let outer = List.find (fun row -> row |> member "name" |> string = "outer") spans in
      let inner = List.find (fun row -> row |> member "name" |> string = "inner") spans in
      check_string "nested trace"
        (outer |> member "traceId" |> string)
        (inner |> member "traceId" |> string);
      check_string "nested parent"
        (outer |> member "spanId" |> string)
        (inner |> member "parentSpanId" |> string))

(* ^notel-1stb: the switch that owns the exporter ends without a caller's shutdown, and
   the record logged just before it still reaches the collector. *)
let release_exports_pending () =
  with_collector (fun env sw client endpoint received ->
      Eio.Switch.run (fun owned ->
          let exporter =
            O.create ~caps:(Ox_test.powerbox ()) ~sw:owned ~clock:env#clock
              ~http_client:client ~endpoint ~service_name:"nema" ()
            |> exporter_ok
          in
          let logger =
            L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
              ~reporter:(O.reporter exporter) ()
          in
          L.info logger "last words");
      let records = log_records !received in
      check_int "the record logged before the release" 1 (List.length records);
      check_string "the last message reached the collector" "last words"
        (List.hd records |> member "body" |> member "stringValue" |> string))

(* ^notel-1stb: the exporter registers its own release hook when it is created, so a
   release hook registered later runs first (releases are LIFO) and the record it logs
   while the switch is stopping is still exported — the shape of a Door SIGTERM stop. *)
let release_hook_records () =
  with_collector (fun env sw client endpoint received ->
      Eio.Switch.run (fun owned ->
          let exporter =
            O.create ~caps:(Ox_test.powerbox ()) ~sw:owned ~clock:env#clock
              ~http_client:client ~endpoint ~service_name:"nema" ()
            |> exporter_ok
          in
          let logger =
            L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
              ~reporter:(O.reporter exporter) ()
          in
          Eio.Switch.on_release owned (fun () -> L.info logger "stopped"));
      let records = log_records !received in
      check_int "the record logged while stopping" 1 (List.length records);
      check_string "it reached the collector" "stopped"
        (List.hd records |> member "body" |> member "stringValue" |> string))

(* ^notel-1stb: a consumer that registers shutdown with the switch's release no longer
   waits for the cancelled worker, and the ending it reads is the one the release
   recorded — a later shutdown returns the same result instead of blocking. *)
let shutdown_in_release () =
  with_collector (fun env sw client endpoint received ->
      let opened = ref None and released = ref None in
      Eio.Switch.run (fun owned ->
          let exporter =
            O.create ~caps:(Ox_test.powerbox ()) ~sw:owned ~clock:env#clock
              ~http_client:client ~endpoint ~service_name:"nema" ()
            |> exporter_ok
          in
          opened := Some exporter;
          Eio.Switch.on_release owned (fun () -> released := Some (O.shutdown exporter));
          let logger =
            L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
              ~reporter:(O.reporter exporter) ()
          in
          L.info logger "last words");
      (match !released with
      | Some (Ok ()) -> ()
      | Some (Error error) ->
          Alcotest.failf "shutdown in a release hook: %a" O.pp_error error
      | None -> Alcotest.fail "the release hook never ran");
      (match O.shutdown (Option.get !opened) with
      | Ok () -> ()
      | Error error -> Alcotest.failf "shutdown after the release: %a" O.pp_error error);
      let requests = List.length !received in
      check_int "the queue was exported exactly once" 1 requests;
      check_int "and it carried the pending record" 1
        (List.length (log_records !received)))

let spans_without_ids_remain_logs () =
  (* ^notel-6m2q: enabling the exporter without ID generation must preserve
     both legacy start/end records as logs rather than silently drop the start. *)
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:(O.reporter exporter) ()
      in
      ignore (L.span logger "legacy" (fun () -> Ok ()) : (unit, string) result);
      exporter_ok (O.shutdown exporter);
      let records =
        List.concat_map
          (fun request ->
            request.body |> first "resourceLogs" |> first "scopeLogs"
            |> member "logRecords" |> list)
          !received
      in
      check_int "start and end remain logs" 2 (List.length records))

(* ^notel-na2w: the collector refuses only traces; a log from the same span
   still succeeds, while both failure callbacks keep their respective contracts. *)
let trace_failure_names_signal () =
  with_collector ~refuse_traces:true (fun env sw client endpoint received ->
      let errors = ref [] and signal_errors = ref [] in
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema"
          ~on_error:(fun error -> errors := error :: !errors)
          ~on_signal_error:(fun signal error ->
            signal_errors := (signal, error) :: !signal_errors)
          ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~span_ids:(O.span_ids exporter) ~reporter:(O.reporter exporter) ()
      in
      ignore
        (L.span logger "refused trace" (fun () ->
             L.info logger "accepted log";
             Ok ())
          : (unit, string) result);
      (match O.flush exporter with
      | Error (`Status 503) -> ()
      | _ -> Alcotest.fail "trace refusal must reach flush");
      check_int "log exported" 1 (List.length (log_records !received));
      check_int "one legacy error" 1 (List.length !errors);
      check_int "one signal error" 1 (List.length !signal_errors);
      (match !signal_errors with
      | [ (O.Traces, `Status 503) ] -> ()
      | _ -> Alcotest.fail "only the trace failure should be named Traces");
      exporter_ok (O.shutdown exporter))

let bounded_and_failure () =
  (* ^notel-p4xe ^notel-t8br: full queue rejects newest; failure reported on
     shutdown, not as a false drained success. No collector body is surfaced. *)
  with_collector ~status:503 (fun env sw client endpoint received ->
      let errors = ref [] in
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ~max_queue:2 ~batch_size:2
          ~on_error:(fun error -> errors := error :: !errors)
          ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:(O.reporter exporter) ()
      in
      for i = 1 to 5 do
        L.info logger (string_of_int i)
      done;
      Alcotest.(check bool) "bounded drops newest" true (O.dropped exporter > 0);
      (match O.shutdown exporter with
      | Error (`Status 503) -> ()
      | _ -> Alcotest.fail "collector failure must reach shutdown");
      let delivered =
        List.fold_left
          (fun count request ->
            count
            + (request.body |> first "resourceLogs" |> first "scopeLogs"
             |> member "logRecords" |> list |> List.length))
          0 !received
      in
      check_int "accepted plus dropped" 5 (delivered + O.dropped exporter);
      check_int "one callback per failed batch" (List.length !received)
        (List.length !errors))

(* ^notel-6o5v ^notel-jzdm: the API key and the tenant accompany every export request,
   logs and traces alike, with the resource attributes beside the exporter's own
   [service.name]; no header value reaches a request body. *)
let headers_and_resource_on_the_wire () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema"
          ~resource:
            [ ("service.version", "1.2.3"); ("deployment.environment", "staging") ]
          ~headers:[ ("authorization", "Bearer sk-live-secret"); ("x-tenant", "acme") ]
          ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~span_ids:(O.span_ids exporter) ~reporter:(O.reporter exporter) ()
      in
      L.info logger "hello";
      ignore (L.span logger "unit" (fun () -> Ok ()) : (unit, string) result);
      exporter_ok (O.shutdown exporter);
      check_int "one logs and one traces request" 2 (List.length !received);
      List.iter
        (fun request ->
          Alcotest.(check (option string))
            (request.target ^ " carries the API key")
            (Some "Bearer sk-live-secret")
            (header request.headers "authorization");
          Alcotest.(check (option string))
            "and the tenant" (Some "acme")
            (header request.headers "x-tenant");
          let wrapper =
            if contains request.target "traces" then "resourceSpans" else "resourceLogs"
          in
          let attrs =
            request.body |> first wrapper |> member "resource" |> member "attributes"
            |> list
          in
          check_string "the exporter's identity" "nema" (string_attr attrs "service.name");
          check_string "^notel-jzdm the build is distinguishable" "1.2.3"
            (string_attr attrs "service.version");
          check_string "^notel-jzdm and the environment is named" "staging"
            (string_attr attrs "deployment.environment");
          check_int "one resource identity, never a duplicate" 1
            (List.length
               (List.filter
                  (fun attr -> attr |> member "key" |> string = "service.name")
                  attrs)))
        !received;
      Alcotest.(check bool)
        "^notel-6o5v the secret never reaches a request body" false
        (List.exists
           (fun request -> contains (Yojson.Safe.to_string request.body) "sk-live-secret")
           !received))

(* ^notel-6o5v: a refused export reports a typed failure that renders neither the header
   names nor their values. *)
let header_values_never_rendered () =
  with_collector ~status:503 (fun env sw client endpoint _received ->
      let errors = ref [] in
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema"
          ~headers:[ ("authorization", "Bearer sk-live-secret") ]
          ~on_error:(fun error -> errors := error :: !errors)
          ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:(O.reporter exporter) ()
      in
      L.info logger "hello";
      (match O.shutdown exporter with
      | Error (`Status 503) -> ()
      | _ -> Alcotest.fail "collector failure must reach shutdown");
      Alcotest.(check bool)
        "the failure reached the callback" true
        (List.length !errors > 0);
      List.iter
        (fun error ->
          let rendered = Format.asprintf "%a" O.pp_error error in
          Alcotest.(check bool)
            ("no secret in " ^ rendered) false
            (contains rendered "sk-live-secret");
          Alcotest.(check bool)
            ("no header name in " ^ rendered)
            false
            (contains rendered "authorization"))
        !errors)

let flush_failure_and_closed () =
  (* ^notel-p4xe ^notel-t8br: flush returns the failed batch once; a sealed
     exporter refuses further flushes and repeated shutdown stays idempotent. *)
  with_collector ~status:503 (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:(O.reporter exporter) ()
      in
      L.info logger "first";
      (match O.flush exporter with
      | Error (`Status 503) -> ()
      | _ -> Alcotest.fail "flush must report collector failure");
      exporter_ok (O.shutdown exporter);
      exporter_ok (O.shutdown exporter);
      (match O.flush exporter with
      | Error `Closed -> ()
      | _ -> Alcotest.fail "flush after shutdown must be closed");
      check_int "one failed request" 1 (List.length !received))

let wait_for_metrics env received =
  (* ^notel-8ixo: the interval is real time, so the test polls the collector instead of
     assuming a scheduler; the surrounding timeout fails it rather than hanging. *)
  let rec loop remaining =
    if metric_rows !received <> [] then ()
    else if remaining = 0 then Alcotest.fail "the metrics window was never exported"
    else begin
      Eio.Time.sleep env#clock 0.01;
      loop (remaining - 1)
    end
  in
  loop 300

(* ^notel-bez2 ^notel-8ixo ^notel-jzdm: counter, up-down counter and histogram reach the
   collector's metrics path with the exporter's resource attributes and headers, and a
   flush settles the window. *)
let counter_and_histogram_on_the_wire () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema"
          ~resource:[ ("service.version", "1.2.3") ]
          ~headers:[ ("authorization", "Bearer sk-live-secret") ]
          ()
        |> exporter_ok
      in
      let meter = O.meter exporter in
      let requests =
        O.Meter.counter meter ~name:"http.requests" ~unit_:"{request}"
          ~attrs:[ ("route", "/query") ]
          ()
      in
      O.Meter.add requests 2.0;
      O.Meter.add requests 3.0;
      let depth = O.Meter.up_down_counter meter ~name:"queue.depth" () in
      O.Meter.add depth 4.0;
      O.Meter.add depth (-6.0);
      let latency =
        O.Meter.histogram meter ~name:"http.duration" ~unit_:"ms"
          ~boundaries:[ 10.0; 20.0 ]
          ~attrs:[ ("route", "/query") ]
          ()
      in
      List.iter (O.Meter.record latency) [ 5.0; 15.0; 25.0 ];
      exporter_ok (O.flush exporter);
      exporter_ok (O.shutdown exporter);
      check_int "metrics alone: one request" 1 (List.length !received);
      let request = List.hd !received in
      Alcotest.(check bool)
        "the metrics path" true
        (String.ends_with ~suffix:"/otlp/v1/metrics HTTP/1.1" request.target);
      Alcotest.(check (option string))
        "the collector's API key accompanies the window" (Some "Bearer sk-live-secret")
        (header request.headers "authorization");
      let resource =
        request.body |> first "resourceMetrics" |> member "resource"
        |> member "attributes" |> list
      in
      check_string "the exporter's identity" "nema" (attr resource "service.name");
      check_string "^notel-jzdm the build is distinguishable" "1.2.3"
        (attr resource "service.version");
      let rows = metric_rows !received in
      Alcotest.(check int) "three instruments, three metrics" 3 (List.length rows);
      let counter = metric_named "http.requests" !received in
      Alcotest.(check (float 0.001))
        "the counter's window sum" 5.0
        (data_point counter "sum" |> member "asDouble" |> Yojson.Safe.Util.to_float);
      check_string "the data point's attributes" "/query"
        (attr (data_point counter "sum" |> member "attributes" |> list) "route");
      let up_down = metric_named "queue.depth" !received in
      Alcotest.(check bool)
        "an up-down counter is not monotonic" false
        (up_down |> member "sum" |> member "isMonotonic" |> Yojson.Safe.Util.to_bool);
      Alcotest.(check (float 0.001))
        "signed increments are summed within the window" (-2.0)
        (data_point up_down "sum" |> member "asDouble" |> Yojson.Safe.Util.to_float);
      let histogram = metric_named "http.duration" !received in
      let point = data_point histogram "histogram" in
      check_string "the histogram's count" "3" (point |> member "count" |> string);
      Alcotest.(check (list string))
        "its buckets, overflow last" [ "1"; "1"; "1" ]
        (point |> member "bucketCounts" |> list |> List.map string))

(* ^notel-8ixo ^notel-1stb: the switch that owns the exporter exports the window it
   still holds when it ends, without a caller's shutdown. *)
let metrics_drain_on_release () =
  with_collector (fun env sw client endpoint received ->
      Eio.Switch.run (fun owned ->
          let exporter =
            O.create ~caps:(Ox_test.powerbox ()) ~sw:owned ~clock:env#clock
              ~http_client:client ~endpoint ~service_name:"nema" ()
            |> exporter_ok
          in
          let meter = O.meter exporter in
          let counter = O.Meter.counter meter ~name:"release.total" () in
          O.Meter.add counter 7.0);
      check_int "the releasing fiber exported the window" 1 (List.length !received);
      Alcotest.(check (float 0.001))
        "the measurement taken before the release" 7.0
        (data_point (metric_named "release.total" !received) "sum"
        |> member "asDouble" |> Yojson.Safe.Util.to_float))

(* ^notel-8ixo: the interval posts the window on its own, with no flush. *)
let metrics_exported_periodically () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ~metrics_interval:(Ox.Duration.ms 30) ()
        |> exporter_ok
      in
      let meter = O.meter exporter in
      let ticks = O.Meter.counter meter ~name:"tick.total" () in
      O.Meter.add ticks 1.0;
      wait_for_metrics env received;
      Alcotest.(check (float 0.001))
        "the interval posted the measurement" 1.0
        (data_point (metric_named "tick.total" !received) "sum"
        |> member "asDouble" |> Yojson.Safe.Util.to_float);
      exporter_ok (O.shutdown exporter))

(* ^notel-8ixo: a window is taken once, so flushing again posts nothing. This is the
   steady-state half of the at-least-once rule the release drain relies on: a duplicate
   window can only come from an interrupted send, never from a completed one. *)
let drained_window_is_not_reposted () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ~metrics_interval:(Ox.Duration.seconds 3600) ()
        |> exporter_ok
      in
      let meter = O.meter exporter in
      let counter = O.Meter.counter meter ~name:"drained.total" () in
      O.Meter.add counter 1.0;
      exporter_ok (O.flush exporter);
      let posted = List.length !received in
      check_int "the window was posted once" 1 posted;
      exporter_ok (O.flush exporter);
      check_int "the second flush has nothing to post" posted (List.length !received);
      exporter_ok (O.shutdown exporter))

(* ^notel-8ixo: a worker busy with logs still exports the metrics window on its
   interval — the wait is bounded by the time left, not re-armed by every record. *)
let metrics_export_under_load () =
  with_collector (fun env sw client endpoint received ->
      (* The exporter lives on its own switch, so a failing assertion still drains
         against a live collector instead of waiting on one the teardown cancelled. *)
      Eio.Switch.run (fun owned ->
          let exporter =
            O.create ~caps:(Ox_test.powerbox ()) ~sw:owned ~clock:env#clock
              ~http_client:client ~endpoint ~service_name:"nema"
              ~metrics_interval:(Ox.Duration.ms 40) ()
            |> exporter_ok
          in
          let logger =
            L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
              ~reporter:(O.reporter exporter) ()
          in
          let meter = O.meter exporter in
          let counter = O.Meter.counter meter ~name:"busy.total" () in
          O.Meter.add counter 1.0;
          let deadline = Eio.Time.now env#clock +. 0.3 in
          let exported_during_load = ref false in
          while Eio.Time.now env#clock < deadline do
            L.info logger "busy";
            if metric_rows !received <> [] then exported_during_load := true;
            Eio.Time.sleep env#clock 0.005
          done;
          Alcotest.(check bool)
            "the window was exported while logs kept arriving" true !exported_during_load))

(* ^notel-8ixo: the series bound drops the record that would begin one more series and
   counts it, so attribute cardinality a program does not control stays finite. *)
let metric_series_bound () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ~max_metric_series:1 ()
        |> exporter_ok
      in
      let meter = O.meter exporter in
      let admitted = O.Meter.counter meter ~name:"admitted" () in
      let rejected = O.Meter.counter meter ~name:"rejected" () in
      O.Meter.add admitted 1.0;
      O.Meter.add rejected 1.0;
      check_int "the series beyond the bound is counted" 1 (O.dropped exporter);
      exporter_ok (O.flush exporter);
      check_int "only the admitted series reaches the collector" 1
        (List.length (metric_rows !received));
      Alcotest.(check bool)
        "the dropped series is never sent" true
        (metric_row "rejected" !received = None);
      exporter_ok (O.shutdown exporter))

(* ^notel-8ixo: a refused metrics window is a typed failure on flush, never a false
   drained success. *)
let metrics_failure_reaches_flush () =
  with_collector ~status:503 (fun env sw client endpoint _received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ()
        |> exporter_ok
      in
      let meter = O.meter exporter in
      let counter = O.Meter.counter meter ~name:"refused" () in
      O.Meter.add counter 1.0;
      (match O.flush exporter with
      | Error (`Status 503) -> ()
      | _ -> Alcotest.fail "a refused metrics window must reach flush");
      exporter_ok (O.shutdown exporter))

(* Every completed span the collector received, in arrival order. *)
let exported_spans received =
  List.concat_map
    (fun request ->
      if contains request.target "/v1/traces" then
        request.body |> first "resourceSpans" |> first "scopeSpans" |> member "spans"
        |> list
      else [])
    received

let named name rows =
  match List.find_opt (fun row -> row |> member "name" |> string = name) rows with
  | Some row -> row
  | None -> Alcotest.failf "no span named %s on the wire" name

let with_body body rows =
  match
    List.find_opt
      (fun row -> row |> member "body" |> member "stringValue" |> string = body)
      rows
  with
  | Some row -> row
  | None -> Alcotest.failf "no log %S on the wire" body

let attribute_keys row =
  row |> member "attributes" |> list
  |> List.map (fun attr -> attr |> member "key" |> string)

(* ^notel-dzpj ^notel-p11y: one attribute per key, and no trace control among them. *)
let check_attribute_keys label row =
  let keys = attribute_keys row in
  check_int
    (label ^ ": one attribute per key")
    (List.length (List.sort_uniq String.compare keys))
    (List.length keys);
  List.iter
    (fun control ->
      Alcotest.(check bool)
        (label ^ ": " ^ control ^ " is not an attribute")
        false (List.mem control keys))
    [ "trace_id"; "span_id"; "parent_span_id" ]

let attrs_of row = row |> member "attributes" |> list

(* ^notel-nbvl ^notel-uydw ^notel-p11y ^notel-jda9 ^notel-dzpj: inherited business context
   reaches every exported span and its correlated logs through the public exporter; an
   explicit field replaces a duplicate inherited key, once; trace controls stay native IDs;
   forked siblings keep their own context and local fields; a secret stays redacted. *)
let inherited_context_on_spans_and_logs () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema"
          ~resource:[ ("service.version", "context-slice") ]
          ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~span_ids:(O.span_ids exporter) ~reporter:(O.reporter exporter) ()
      in
      let secret = "s3cret-token" in
      let leg provider =
        Ox_observability.Context.with_fields
          [ ("provider", provider) ]
          (fun () ->
            L.span logger ("leg." ^ provider)
              ~fields:[ ("leg.local", String provider) ]
              (fun () ->
                Eio.Fiber.yield ();
                L.info logger ("in leg " ^ provider);
                Eio.Fiber.yield ();
                Ok ()))
      in
      Ox_observability.Context.with_fields
        [
          ("provider", "binance");
          ("endpoint", "/inherited");
          ("db", "ladybug");
          ("symbol", "BTCUSDT");
          ("retry", "inherited");
        ]
        (fun () ->
          let before =
            Ox_observability.Context.fields (Ox_observability.Context.current ())
          in
          ignore
            (L.span logger "outer"
               ~fields:
                 [
                   ("endpoint", String "/explicit");
                   ("outer.local", Bool true);
                   ("token", Redacted (Ox_observability.Redact.make secret));
                   ("trace_id", String "fake-trace");
                   ("span_id", String "fake-span");
                   ("parent_span_id", String "fake-parent");
                 ]
               (fun () ->
                 L.info logger "correlated"
                   ~fields:
                     [
                       ("db", String "explicit-db");
                       ("retry", Int 7);
                       ("trace_id", String "fake-trace");
                       ("span_id", String "fake-span");
                       ("parent_span_id", String "fake-parent");
                       ("token", Redacted (Ox_observability.Redact.make secret));
                     ];
                 ignore
                   (L.span logger "inner"
                      ~fields:[ ("inner.local", Bool true) ]
                      (fun () ->
                        L.info logger "inner-correlated";
                        Ok ())
                     : (unit, string) result);
                 let a, b =
                   Eio.Fiber.pair (fun () -> leg "kraken") (fun () -> leg "okx")
                 in
                 ignore (a : (unit, string) result);
                 ignore (b : (unit, string) result);
                 L.info logger "outer-after-children";
                 Ok ())
              : (unit, string) result);
          Alcotest.(check bool)
            "nested and forked bindings restore the caller" true
            (Ox_observability.Context.fields (Ox_observability.Context.current ())
            = before);
          L.info logger "after-span");
      L.info logger "caller";
      exporter_ok (O.flush exporter);
      let spans = exported_spans !received and logs = log_records !received in
      List.iter
        (fun row -> check_attribute_keys (row |> member "name" |> string) row)
        spans;
      List.iter
        (fun row ->
          check_attribute_keys
            (row |> member "body" |> member "stringValue" |> string)
            row)
        logs;
      let outer = named "outer" spans and inner = named "inner" spans in
      let outer_attrs = attrs_of outer and inner_attrs = attrs_of inner in
      (* ^notel-nbvl: inherited provider, endpoint, symbol and db on parent and child. *)
      List.iter
        (fun (label, attrs) ->
          check_string (label ^ " provider") "binance" (string_attr attrs "provider");
          check_string (label ^ " symbol") "BTCUSDT" (string_attr attrs "symbol");
          check_string (label ^ " db") "ladybug" (string_attr attrs "db"))
        [ ("outer", outer_attrs); ("inner", inner_attrs) ];
      (* ^notel-uydw: the explicit span field wins its duplicate inherited key. *)
      check_string "explicit endpoint wins" "/explicit"
        (string_attr outer_attrs "endpoint");
      check_string "the child inherits the context, not the parent's field" "/inherited"
        (string_attr inner_attrs "endpoint");
      check_string "the parent's local field stays on the parent" "<absent>"
        (string_attr inner_attrs "outer.local");
      check_string "a redacted field stays redacted" "<redacted>"
        (string_attr outer_attrs "token");
      List.iter
        (fun key ->
          check_string
            ("kernel span field " ^ key ^ " is not a business attribute")
            "<absent>" (string_attr outer_attrs key))
        [ "event"; "outcome"; "elapsed_ms"; "error" ];
      (* ^notel-p11y: parentage still comes from the trace controls. *)
      check_int "native trace ID length" 32
        (String.length (outer |> member "traceId" |> string));
      check_int "native span ID length" 16
        (String.length (outer |> member "spanId" |> string));
      Alcotest.(check bool)
        "an explicit field cannot forge root parentage" true
        (member "parentSpanId" outer = `Null);
      check_string "nested trace"
        (outer |> member "traceId" |> string)
        (inner |> member "traceId" |> string);
      check_string "nested parent"
        (outer |> member "spanId" |> string)
        (inner |> member "parentSpanId" |> string);
      (* ^notel-dzpj: the correlated log has the same context, explicit fields winning. *)
      let correlated = attrs_of (with_body "correlated" logs) in
      check_string "log provider" "binance" (string_attr correlated "provider");
      check_string "log endpoint is the context's" "/inherited"
        (string_attr correlated "endpoint");
      check_string "explicit log field wins" "explicit-db" (string_attr correlated "db");
      check_string "log trace stays native"
        (outer |> member "traceId" |> string)
        (with_body "correlated" logs |> member "traceId" |> string);
      check_string "log span stays native"
        (outer |> member "spanId" |> string)
        (with_body "correlated" logs |> member "spanId" |> string);
      check_string "a redacted log field stays redacted" "<redacted>"
        (string_attr correlated "token");
      let retry =
        List.find (fun attr -> attr |> member "key" |> string = "retry") correlated
      in
      check_string "an explicit log value keeps its integer type" "7"
        (retry |> member "value" |> member "intValue" |> string);
      List.iter
        (fun body ->
          let row = with_body body logs in
          let attrs = attrs_of row in
          List.iter
            (fun (key, expected) ->
              check_string (body ^ " inherits " ^ key) expected (string_attr attrs key))
            [
              ("provider", "binance");
              ("endpoint", "/inherited");
              ("db", "ladybug");
              ("symbol", "BTCUSDT");
            ];
          List.iter
            (fun key ->
              check_string (body ^ " has no " ^ key) "<absent>" (string_attr attrs key))
            [ "outer.local"; "inner.local"; "leg.local" ])
        [ "inner-correlated"; "outer-after-children"; "after-span" ];
      check_string "nested log trace stays native"
        (inner |> member "traceId" |> string)
        (with_body "inner-correlated" logs |> member "traceId" |> string);
      check_string "nested log span stays native"
        (inner |> member "spanId" |> string)
        (with_body "inner-correlated" logs |> member "spanId" |> string);
      (* ^notel-jda9: forked siblings keep their own context and local fields. *)
      List.iter
        (fun provider ->
          let span = named ("leg." ^ provider) spans in
          let attrs = attrs_of span in
          check_string (provider ^ " leg provider") provider
            (string_attr attrs "provider");
          check_string (provider ^ " leg inherits db") "ladybug" (string_attr attrs "db");
          check_string (provider ^ " leg local") provider (string_attr attrs "leg.local");
          check_string
            (provider ^ " leg inherits endpoint")
            "/inherited"
            (string_attr attrs "endpoint");
          check_string
            (provider ^ " leg inherits symbol")
            "BTCUSDT" (string_attr attrs "symbol");
          check_string
            (provider ^ " leg has no parent local field")
            "<absent>"
            (string_attr attrs "outer.local");
          check_string (provider ^ " leg parent")
            (outer |> member "spanId" |> string)
            (span |> member "parentSpanId" |> string);
          let log = attrs_of (with_body ("in leg " ^ provider) logs) in
          check_string
            (provider ^ " leg log provider")
            provider (string_attr log "provider");
          check_string
            (provider ^ " leg log has no local span field")
            "<absent>" (string_attr log "leg.local"))
        [ "kraken"; "okx" ];
      List.iter
        (fun key ->
          check_string
            ("no child field leaks to the parent: " ^ key)
            "<absent>" (string_attr outer_attrs key))
        [ "inner.local"; "leg.local" ];
      let caller = with_body "caller" logs and after_span = with_body "after-span" logs in
      List.iter
        (fun key ->
          check_string
            ("no context leaks outside its binding: " ^ key)
            "<absent>"
            (string_attr (attrs_of caller) key))
        [
          "provider";
          "endpoint";
          "db";
          "symbol";
          "outer.local";
          "inner.local";
          "leg.local";
        ];
      List.iter
        (fun row ->
          List.iter
            (fun key ->
              Alcotest.(check bool)
                (key ^ " does not leak out of a span")
                true
                (member key row = `Null))
            [ "traceId"; "spanId" ])
        [ caller; after_span ];
      List.iter
        (fun row ->
          List.iter
            (fun key ->
              check_string
                ("resource identity stays separate: " ^ key)
                "<absent>"
                (string_attr (attrs_of row) key))
            [ "service.name"; "service.version" ])
        (spans @ logs);
      List.iter
        (fun request ->
          Alcotest.(check bool)
            "the secret never reaches the collector" false
            (contains (Yojson.Safe.to_string request.body) secret);
          let envelope =
            if contains request.target "/v1/traces" then "resourceSpans"
            else "resourceLogs"
          in
          let attrs =
            request.body |> first envelope |> member "resource" |> member "attributes"
            |> list
          in
          check_string "resource service name is retained" "nema"
            (string_attr attrs "service.name");
          check_string "resource version is retained" "context-slice"
            (string_attr attrs "service.version"))
        !received;
      exporter_ok (O.shutdown exporter))

(* ^notel-nbvl ^notel-dzpj: a completion field is an ordinary end-record field, so it is a
   span attribute too, winning a duplicate span field once. *)
let completion_fields_on_spans () =
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock ~http_client:client
          ~endpoint ~service_name:"nema" ()
        |> exporter_ok
      in
      let logger =
        L.create ~service:"nema" ~clock:env#clock ~mono_clock:env#mono_clock
          ~span_ids:(O.span_ids exporter) ~reporter:(O.reporter exporter) ()
      in
      ignore
        (L.span logger "request"
           ~fields:[ ("http.status", Int 0) ]
           ~complete:(fun result ->
             match result with
             | Ok status -> [ ("http.status", L.Int status) ]
             | Error _ -> [])
           (fun () -> Ok 204)
          : (int, string) result);
      exporter_ok (O.shutdown exporter);
      let span = named "request" (exported_spans !received) in
      check_attribute_keys "request" span;
      check_string "the completion field is a span attribute" "204"
        (string_attr (attrs_of span) "http.status"))

let () =
  Alcotest.run "ox_otel"
    [
      ( "wire",
        [
          Alcotest.test_case "OTLP JSON envelope and scalars (^notel-z7dk)" `Quick
            wire_encoding;
        ] );
      ( "metrics",
        [
          Alcotest.test_case
            "OTLP metric envelope, delta sums and buckets (^notel-bez2 ^notel-8ixo)"
            `Quick metric_wire_encoding;
          Alcotest.test_case "instruments stamp points and validate bounds (^notel-bez2)"
            `Quick instruments_stamp_points;
          Alcotest.test_case
            "counter and histogram on the wire (^notel-bez2 ^notel-8ixo ^notel-jzdm)"
            `Quick counter_and_histogram_on_the_wire;
          Alcotest.test_case "metrics drain on release (^notel-8ixo ^notel-1stb)" `Quick
            metrics_drain_on_release;
          Alcotest.test_case "the interval posts the window (^notel-8ixo)" `Quick
            metrics_exported_periodically;
          Alcotest.test_case "a drained window is not reposted (^notel-8ixo)" `Quick
            drained_window_is_not_reposted;
          Alcotest.test_case "a busy worker still exports the window (^notel-8ixo)" `Quick
            metrics_export_under_load;
          Alcotest.test_case "the series bound drops and counts (^notel-8ixo)" `Quick
            metric_series_bound;
          Alcotest.test_case "a refused window reaches flush (^notel-8ixo)" `Quick
            metrics_failure_reaches_flush;
        ] );
      ( "exporter",
        [
          Alcotest.test_case
            "logs, nested traces and shutdown (^notel-6m2q ^notel-j9vc ^notel-p4xe \
             ^pcaps-wury)"
            `Quick log_and_spans;
          Alcotest.test_case "release exports the pending queue (^notel-1stb)" `Quick
            release_exports_pending;
          Alcotest.test_case "a release hook's last record is exported (^notel-1stb)"
            `Quick release_hook_records;
          Alcotest.test_case "shutdown inside a release hook returns (^notel-1stb)" `Quick
            shutdown_in_release;
          Alcotest.test_case "legacy spans remain logs (^notel-6m2q)" `Quick
            spans_without_ids_remain_logs;
          Alcotest.test_case "trace refusal names signal (^notel-na2w)" `Quick
            trace_failure_names_signal;
          Alcotest.test_case "bounded queue and typed status (^notel-p4xe ^notel-t8br)"
            `Quick bounded_and_failure;
          Alcotest.test_case
            "headers and resource attributes on the wire (^notel-6o5v ^notel-jzdm)" `Quick
            headers_and_resource_on_the_wire;
          Alcotest.test_case "header values are never rendered (^notel-6o5v)" `Quick
            header_values_never_rendered;
          Alcotest.test_case "flush failure and closed state (^notel-p4xe ^notel-t8br)"
            `Quick flush_failure_and_closed;
        ] );
      ( "context",
        [
          Alcotest.test_case
            "inherited context on spans and logs (^notel-nbvl ^notel-uydw ^notel-p11y \
             ^notel-jda9 ^notel-dzpj)"
            `Quick inherited_context_on_spans_and_logs;
          Alcotest.test_case
            "completion fields are span attributes (^notel-nbvl ^notel-dzpj)" `Quick
            completion_fields_on_spans;
        ] );
    ]
