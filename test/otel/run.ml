module L = Eta_observability.Logger
module O = Eta_otel

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
      ~scope_name:"eta_otel" [ span ]
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
    O.Otlp_json.encode_logs_request ~resource_attrs:[] ~scope_name:"eta_otel" [ record ]
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

let with_collector ?(status = 200) f =
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
                  (Printf.sprintf "HTTP/1.1 %d %s\r\nContent-Length: 0\r\n\r\n" status
                     (if status = 200 then "OK" else "Unavailable"))
                  flow
              done;
              `Stop_daemon);
          let client = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
          let endpoint = Printf.sprintf "http://127.0.0.1:%d/otlp" port in
          f env sw client endpoint received))

let exporter_ok result =
  match result with
  | Ok x -> x
  | Error err -> Alcotest.failf "exporter error: %a" O.pp_error err

let log_and_spans () =
  (* ^notel-6m2q ^notel-j9vc ^notel-p4xe: one logger, two signal endpoints,
     nested spans, correlated logs, explicit drain before borrowed client release. *)
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~sw ~clock:env#clock ~http_client:client ~endpoint ~service_name:"nema"
          ()
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

let spans_without_ids_remain_logs () =
  (* ^notel-6m2q: enabling the exporter without ID generation must preserve
     both legacy start/end records as logs rather than silently drop the start. *)
  with_collector (fun env sw client endpoint received ->
      let exporter =
        O.create ~sw ~clock:env#clock ~http_client:client ~endpoint ~service_name:"nema"
          ()
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

let bounded_and_failure () =
  (* ^notel-p4xe ^notel-t8br: full queue rejects newest; failure reported on
     shutdown, not as a false drained success. No collector body is surfaced. *)
  with_collector ~status:503 (fun env sw client endpoint received ->
      let errors = ref [] in
      let exporter =
        O.create ~sw ~clock:env#clock ~http_client:client ~endpoint ~service_name:"nema"
          ~max_queue:2 ~batch_size:2
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
        O.create ~sw ~clock:env#clock ~http_client:client ~endpoint ~service_name:"nema"
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
        O.create ~sw ~clock:env#clock ~http_client:client ~endpoint ~service_name:"nema"
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
        O.create ~sw ~clock:env#clock ~http_client:client ~endpoint ~service_name:"nema"
          ()
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

let () =
  Alcotest.run "eta_otel"
    [
      ( "wire",
        [
          Alcotest.test_case "OTLP JSON envelope and scalars (^notel-z7dk)" `Quick
            wire_encoding;
        ] );
      ( "exporter",
        [
          Alcotest.test_case
            "logs, nested traces and shutdown (^notel-6m2q ^notel-j9vc ^notel-p4xe)"
            `Quick log_and_spans;
          Alcotest.test_case "legacy spans remain logs (^notel-6m2q)" `Quick
            spans_without_ids_remain_logs;
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
    ]
