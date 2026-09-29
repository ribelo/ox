module Logger = Eta_observability.Logger
module Otlp_json = Otlp_json
module Json = Otlp_json
module Meter = Meter
module Metric_aggregation = Metric_aggregation

type error =
  [ `Invalid_config of string
  | `Http of Eta_http.Client.error
  | `Status of int
  | `Closed
  | `Drain_deadline ]

type signal = Logs | Traces | Metrics

let pp_error ppf = function
  | `Invalid_config reason -> Format.fprintf ppf "invalid OTLP configuration: %s" reason
  | `Http _ -> Format.pp_print_string ppf "OTLP HTTP transport failed"
  | `Status status -> Format.fprintf ppf "OTLP collector returned HTTP %d" status
  | `Closed -> Format.pp_print_string ppf "OTLP exporter is closed"
  | `Drain_deadline -> Format.pp_print_string ppf "OTLP drain deadline reached"

type item = Log of Logger.record | Span of Json.span
type command = Item of item | Flush of (unit, error) result Eio.Promise.u | Stop

(* ^notel-1stb: one ending per exporter. The worker resolves it when it takes [Stop];
   a release resolves the same one — Eio cancels a switch's fibers before it runs its
   release hooks, so the worker is already gone by then and the exporter exports the
   queue's remainder itself. Every [shutdown] reads that one result. *)
type ending = {
  stop : (unit, error) result Eio.Promise.t;
  resolve : (unit, error) result Eio.Promise.u;
}

type t = {
  queue : command Eio.Stream.t;
  http_client : Eta_http.Client.t;
  logs_url : string;
  traces_url : string;
  metrics_url : string;
  resource_attrs : (string * string) list;
  scope_name : string;
  batch_size : int;
  max_queue : int;
  request_deadline : Eta.Duration.t option;
  headers : (string * string) list;
  on_error : error -> unit;
  on_signal_error : signal -> error -> unit;
  with_timeout : float -> (unit -> (unit, error) result) -> (unit, error) result;
  (* ^notel-8ixo: the worker blocks here at most [seconds]: a command when one arrives,
     [None] when that wait expires. Built in [create] because the exporter's clock is
     polymorphic and a record field cannot hold it. *)
  wait : float -> command option;
  metrics_interval_ms : int;
  now_ms : unit -> int;
  ids : Random.State.t;
  mutable dropped : int;
  metrics : Metric_aggregation.t;
  mutable pending_metric_rows : Metric_aggregation.row list option;
  mutable closed : bool;
  mutable stopping : bool;
  mutable worker_done : bool;
  mutable first_failure : error option;
  mutable ending : ending option;
  mutable pending : command option;
  mutable in_flight : item list;
}

let dropped t = t.dropped

let span_ids t () =
  let hex = "0123456789abcdef" in
  String.init 32 (fun _ -> hex.[Random.State.int t.ids 16])

let valid_hex length id =
  String.length id = length
  && String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) id

let span_of_end (record : Logger.record) =
  let field key = List.assoc_opt key record.fields in
  let context key = List.assoc_opt key record.context in
  match (context "trace_id", context "span_id", field "elapsed_ms") with
  | Some trace_id, Some span_id, Some (Logger.Int elapsed_ms)
    when valid_hex 32 trace_id && valid_hex 16 span_id ->
      let end_unix_ns = Json.unix_ns record.ts in
      let elapsed_ns = Int64.mul (Int64.of_int (max 0 elapsed_ms)) 1_000_000L in
      let attrs =
        List.filter_map
          (fun (key, value) ->
            if List.mem key [ "event"; "outcome"; "elapsed_ms"; "error" ] then None
            else Some (key, Format.asprintf "%a" Logger.pp_value value))
          record.fields
      in
      let outcome =
        match field "outcome" with Some (Logger.String value) -> value | _ -> ""
      in
      Some
        {
          Json.trace_id;
          span_id;
          parent_span_id =
            (match context "parent_span_id" with
            | Some id when valid_hex 16 id -> Some id
            | _ -> None);
          name = record.msg;
          start_unix_ns = Int64.sub end_unix_ns elapsed_ns;
          end_unix_ns;
          attrs;
          status_code =
            (if outcome = "ok" then 1 else if outcome = "interrupt" then 0 else 2);
          status_message = (if outcome = "ok" then "" else outcome);
        }
  | _ -> None

let submit t item =
  if not t.closed then
    if Eio.Stream.length t.queue >= t.max_queue then t.dropped <- t.dropped + 1
    else Eio.Stream.add t.queue (Item item)

let reporter t =
  Logger.Reporter.records (fun record ->
      match List.assoc_opt "event" record.fields with
      | Some (Logger.String "start")
        when match
               ( List.assoc_opt "trace_id" record.context,
                 List.assoc_opt "span_id" record.context )
             with
             | Some trace_id, Some span_id ->
                 valid_hex 32 trace_id && valid_hex 16 span_id
             | _ -> false ->
          ()
      | Some (Logger.String "end") -> (
          match span_of_end record with
          | Some span -> submit t (Span span)
          | None -> submit t (Log record))
      | _ -> submit t (Log record))

(* The one place a signal leaves the exporter: content type first, the caller's headers
   beside it, the configured deadline. A collector answers with a small JSON body ({} or an
   OTLP partialSuccess); it is read within a small bound and ignored. Metrics, logs and
   traces share it, so a collector that accepts one accepts the others. *)
let post t ~url body =
  match
    Eta_http.Client.request t.http_client ~method_:"POST" ~url
      ~headers:(("content-type", "application/json") :: t.headers)
      ~body:(Bytes.of_string body) ?deadline:t.request_deadline ~max_body_bytes:65536 ()
  with
  | Ok { status; _ } when status >= 200 && status < 300 -> Ok ()
  | Ok { status; _ } -> Error (`Status status)
  | Error error -> Error (`Http error)

let send t items =
  match items with
  | [] -> Ok ()
  | first :: _ -> (
      match first with
      | Log _ ->
          let records =
            List.filter_map (function Log r -> Some r | Span _ -> None) items
          in
          post t ~url:t.logs_url
            (Json.encode_logs_request ~resource_attrs:t.resource_attrs
               ~scope_name:t.scope_name records)
      | Span _ ->
          let spans =
            List.filter_map (function Span s -> Some s | Log _ -> None) items
          in
          post t ~url:t.traces_url
            (Json.encode_traces_request ~resource_attrs:t.resource_attrs
               ~scope_name:t.scope_name spans))

let same_signal a b =
  match (a, b) with Log _, Log _ | Span _, Span _ -> true | _ -> false

let ending t =
  match t.ending with
  | Some ending -> ending
  | None ->
      let stop, resolve = Eio.Promise.create () in
      let ending = { stop; resolve } in
      t.ending <- Some ending;
      ending

(* ^notel-p4xe: the first failure since the previous flush is reported once, by the
   flush or the shutdown that settles it. The worker and the release drain share it. *)
let note t signal = function
  | Ok () -> ()
  | Error error -> (
      if t.first_failure = None then t.first_failure <- Some error;
      (try t.on_error error with _ -> ());
      (* ^notel-na2w: a legacy callback defect must not hide the signal hook. *)
      try t.on_signal_error signal error with _ -> ())

let settled t =
  let result = match t.first_failure with None -> Ok () | Some error -> Error error in
  t.first_failure <- None;
  result

let send_metrics t rows =
  if rows = [] then Ok ()
  else
    post t ~url:t.metrics_url
      (Json.encode_metrics_request ~resource_attrs:t.resource_attrs
         ~scope_name:t.scope_name rows)

(* ^notel-8ixo: one metrics window leaves the exporter here. The window a worker was
   posting when it was cancelled is recorded in [pending_metric_rows], so the release
   drain re-sends it before the window the exporter still holds: an interruption costs a
   duplicate window, never a lost one. Aggregation is at record time, so a full log or
   trace queue never costs a measurement. *)
let export_metrics t =
  let send_window rows =
    if rows <> [] then begin
      t.pending_metric_rows <- Some rows;
      note t Metrics (send_metrics t rows);
      t.pending_metric_rows <- None
    end
  in
  (match t.pending_metric_rows with
  | Some rows ->
      t.pending_metric_rows <- None;
      send_window rows
  | None -> ());
  send_window (Metric_aggregation.drain t.metrics)

(* ^notel-1stb: exports everything the queue still holds, in the same signal batches the
   worker would have sent, and settles every flush waiting there. Eio cancels a switch's
   fibers before it runs its release hooks, so this is the export of last resort; it runs
   under [Cancel.protect] because a release happens on the cancellation path and these
   records have nowhere else to go. Each request keeps the exporter's own bounded
   [request_deadline]. *)
let drain t =
  Eio.Cancel.protect (fun () ->
      let items = ref [] and flushes = ref [] and stopped = ref false in
      let take_command = function
        | Item item -> items := item :: !items
        | Flush resolve -> flushes := resolve :: !flushes
        | Stop -> stopped := true
      in
      (* The worker is gone, but it may have taken records out of the queue before it
         was cancelled: the batch it was sending and the command it had set aside are
         recovered here, in order, or they would be lost with the worker. *)
      List.iter (fun item -> take_command (Item item)) t.in_flight;
      Option.iter take_command t.pending;
      t.in_flight <- [];
      t.pending <- None;
      let rec collect () =
        match Eio.Stream.take_nonblocking t.queue with
        | Some command ->
            take_command command;
            collect ()
        | None -> ()
      in
      collect ();
      let rec batches = function
        | [] -> []
        | first :: rest ->
            let rec take count reversed rest =
              match rest with
              | next :: rest when count < t.batch_size && same_signal first next ->
                  take (count + 1) (next :: reversed) rest
              | rest -> (List.rev reversed, rest)
            in
            let batch, rest = take 1 [ first ] rest in
            batch :: batches rest
      in
      List.iter
        (function
          | [] -> ()
          | first :: _ as batch ->
              let signal = match first with Log _ -> Logs | Span _ -> Traces in
              note t signal (send t batch))
        (batches (List.rev !items));
      export_metrics t;
      let result = settled t in
      List.iter (fun resolve -> Eio.Promise.resolve resolve result) !flushes;
      if !stopped then
        (* A queued [Stop] is a [shutdown] waiting for this ending. *)
        ignore (Eio.Promise.try_resolve (ending t).resolve result : bool);
      result)

(* ^notel-1stb: the exporter's ending, whoever reaches it first: it seals admission,
   exports what the queue still holds without the worker, and records the result every
   later [shutdown] reads. *)
let finish t =
  let recorded = ending t in
  match Eio.Promise.peek recorded.stop with
  | Some result -> result
  | None -> (
      t.closed <- true;
      let drained = drain t in
      ignore (Eio.Promise.try_resolve recorded.resolve drained : bool);
      (* [drain] resolves the ending itself when a queued [Stop] carried its resolver. *)
      match Eio.Promise.peek recorded.stop with
      | Some result -> result
      | None -> drained)

let worker t =
  (* ^notel-8ixo: the metrics window is exported once the interval has elapsed, whether
     the worker spent it idle or carrying logs and traces, so a busy exporter cannot
     starve its metrics; each export re-arms the deadline, and the wait is bounded by
     the time that remains. A flush or a stop exports the window there and then, because
     it must settle what was recorded before it. *)
  let due = ref (t.now_ms () + t.metrics_interval_ms) in
  let flush_window () =
    export_metrics t;
    due := t.now_ms () + t.metrics_interval_ms
  in
  let rec loop () : unit =
    let command =
      match t.pending with
      | Some command ->
          t.pending <- None;
          Some command
      | None -> t.wait (float_of_int (max 0 (!due - t.now_ms ())) /. 1000.)
    in
    (match command with
    | None -> ()
    | Some (Flush resolve) ->
        flush_window ();
        Eio.Promise.resolve resolve (settled t)
    | Some Stop ->
        flush_window ();
        Eio.Promise.resolve (ending t).resolve (settled t)
    | Some (Item item) ->
        let rec gather count reversed =
          if count = t.batch_size then List.rev reversed
          else
            match Eio.Stream.take_nonblocking t.queue with
            | Some (Item next) when same_signal item next ->
                gather (count + 1) (next :: reversed)
            | Some next ->
                t.pending <- Some next;
                List.rev reversed
            | None -> List.rev reversed
        in
        (* ^notel-1stb: the batch is recorded before it is sent, so a cancellation in
           the middle of the request leaves it to the release drain instead of losing
           it. A batch that reached the collector while the response was being read is
           exported twice: at-least-once beats dropping the last records before a
           stop. *)
        t.in_flight <- gather 1 [ item ];
        note t (match item with Log _ -> Logs | Span _ -> Traces) (send t t.in_flight);
        t.in_flight <- [];
        ());
    if t.now_ms () >= !due then flush_window ();
    loop ()
  in
  loop ()

let create ~sw ~clock ~http_client ~endpoint ~service_name ?(scope_name = "eta_otel")
    ?(resource = []) ?(headers = []) ?(batch_size = 64) ?(max_queue = 1024)
    ?(metrics_interval = Eta.Duration.seconds 60) ?(max_metric_series = 1024)
    ?request_deadline ?(on_error = fun _ -> ()) ?(on_signal_error = fun _ _ -> ()) () =
  if batch_size < 1 || max_queue < 1 || max_metric_series < 1 then
    Error (`Invalid_config "batch_size, max_queue and max_metric_series must be positive")
  else if Eta.Duration.compare metrics_interval Eta.Duration.zero <= 0 then
    Error (`Invalid_config "metrics_interval must be positive")
  else if String.trim service_name = "" then
    Error (`Invalid_config "service_name must not be empty")
  else
    match Eta_http.Url.parse endpoint with
    | Error issue -> Error (`Invalid_config (Eta_http.Url.parse_error_to_string issue))
    | Ok url when Eta_http.Url.query url <> None || Eta_http.Url.fragment url <> None ->
        Error (`Invalid_config "OTLP endpoint cannot contain query or fragment")
    | Ok _ ->
        let endpoint = String.trim endpoint in
        let base =
          if String.ends_with ~suffix:"/" endpoint then
            String.sub endpoint 0 (String.length endpoint - 1)
          else endpoint
        in
        let queue = Eio.Stream.create max_queue in
        let t =
          {
            queue;
            http_client;
            logs_url = base ^ "/v1/logs";
            traces_url = base ^ "/v1/traces";
            metrics_url = base ^ "/v1/metrics";
            (* ^notel-jzdm: the exporter's own identity stays first; a caller's duplicate
               [service.name] would be a second, contradictory resource identity. *)
            resource_attrs =
              ("service.name", service_name)
              :: List.filter (fun (name, _) -> name <> "service.name") resource;
            scope_name;
            batch_size;
            max_queue;
            request_deadline;
            headers;
            on_error;
            on_signal_error;
            with_timeout = (fun seconds f -> Eio.Time.with_timeout_exn clock seconds f);
            wait =
              (fun seconds ->
                match
                  Eio.Time.with_timeout clock seconds (fun () ->
                      Ok (Eio.Stream.take queue))
                with
                | Ok command -> Some command
                | Error `Timeout -> None);
            metrics_interval_ms = max 1 (Eta.Duration.to_ms metrics_interval);
            now_ms = (fun () -> int_of_float (Eio.Time.now clock *. 1000.));
            ids = Random.State.make_self_init ();
            dropped = 0;
            metrics = Metric_aggregation.create ~max_series:max_metric_series;
            pending_metric_rows = None;
            closed = false;
            stopping = false;
            worker_done = false;
            first_failure = None;
            ending = None;
            pending = None;
            in_flight = [];
          }
        in
        Eio.Fiber.fork_daemon ~sw (fun () ->
            Fun.protect ~finally:(fun () -> t.worker_done <- true) (fun () -> worker t);
            `Stop_daemon);
        (* ^notel-1stb: Eio cancels a switch's fibers before it runs its release hooks,
           so the daemon above is gone by the time this runs; the exporter exports the
           queue's remainder here, in the releasing fiber, instead of leaving it to a
           worker that cannot run. Registered during [create], so release hooks
           registered later — a program's own, on a Door stop — run first and the last
           records they log are still exported. *)
        Eio.Switch.on_release sw (fun () -> ignore (finish t : (unit, error) result));
        Ok t

(* ^notel-bez2: instruments record into the exporter's own aggregation table — one table
   per exporter, single domain — and a record that would add a series beyond
   [max_metric_series] is counted as dropped instead of growing memory without bound. *)
let meter t =
  Meter.create ~now_ms:t.now_ms ~record:(fun point ->
      if not t.closed then
        if not (Metric_aggregation.add t.metrics point) then t.dropped <- t.dropped + 1)

let flush t =
  if t.closed then Error `Closed
  else if t.worker_done then
    (* ^notel-1stb: no worker is left to take the command — the switch cancelled it —
       so the queue is settled here rather than waiting for one that cannot run. *)
    drain t
  else
    let wait, resolve = Eio.Promise.create () in
    Eio.Stream.add t.queue (Flush resolve);
    Eio.Promise.await wait

let shutdown ?timeout t =
  let recorded = ending t in
  if (not (Eio.Promise.is_resolved recorded.stop)) && not t.stopping then begin
    t.stopping <- true;
    t.closed <- true;
    (* ^notel-1stb: a worker the switch has already cancelled never takes another
       command, so the queue is exported here, in the caller, instead. *)
    if t.worker_done then ignore (finish t : (unit, error) result)
    else Eio.Stream.add t.queue Stop
  end;
  match timeout with
  | None -> Eio.Promise.await recorded.stop
  | Some duration -> (
      try
        t.with_timeout (Eta.Duration.to_seconds_float duration) (fun () ->
            Eio.Promise.await recorded.stop)
      with Eio.Time.Timeout -> Error `Drain_deadline)
