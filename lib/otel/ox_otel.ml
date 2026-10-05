module Logger = Ox_observability.Logger
module Otlp_json = Otlp_json
module Json = Otlp_json
module Meter = Meter
module Metric_aggregation = Metric_aggregation

type error =
  [ `Invalid_config of string
  | `Http of Ox_http.Client.error
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

type control = {
  wait : (unit, error) result Eio.Promise.t;
  resolve : (unit, error) result Eio.Promise.u;
}

type command = Item of item | Flush of control | End
type abandoned = { logs : int; spans : int; metric_series : int; controls : int }

let nothing_abandoned = { logs = 0; spans = 0; metric_series = 0; controls = 0 }

type ending = {
  stop : (unit, error) result Eio.Promise.t;
  resolve : (unit, error) result Eio.Promise.u;
  begun : unit Eio.Promise.t;
  begin_ : unit Eio.Promise.u;
  mutable started_at : Mtime.t option;
}

type t = {
  queue : (command, unit) Ox.Channel.t;
  http_client : Ox_http.Client.t;
  logs_url : string;
  traces_url : string;
  metrics_url : string;
  resource_attrs : (string * string) list;
  scope_name : string;
  batch_size : int;
  request_deadline : Ox.Duration.t option;
  headers : (string * string) list;
  on_error : error -> unit;
  on_signal_error : signal -> error -> unit;
  mono_clock : Eio.Time.Mono.ty Eio.Resource.t;
  clock : float Eio.Time.clock_ty Eio.Resource.t;
  metrics_interval_seconds : float;
  ending_seconds : float;
  ids : Random.State.t;
  mutable dropped : int;
  metrics : Metric_aggregation.t;
  mutable pending_metric_rows : Metric_aggregation.row list option;
  mutable closed : bool;
  mutable worker_done : bool;
  retired : unit Eio.Promise.t;
  retire : unit Eio.Promise.u;
  mutable worker_cancel : Eio.Cancel.t option;
  mutable retiring : bool;
  mutable finishing : bool;
  mutable worker_result : (unit, error) result option;
  mutable first_failure : error option;
  ending : ending;
  mutable controls : control list;
  mutable abandoned : abandoned;
  mutable pending : command option;
  mutable in_flight : item list;
  mutable recovering : item list;
}

let dropped t = t.dropped
let abandoned t = t.abandoned

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
      (* ^notel-nbvl ^notel-uydw ^notel-dzpj: inherited business context and explicit
         fields, one per key; the kernel's lifecycle fields are the span's own shape. *)
      let attrs =
        List.filter_map
          (fun (key, value) ->
            if List.mem key [ "event"; "outcome"; "elapsed_ms"; "error" ] then None
            else Some (key, Format.asprintf "%a" Logger.pp_value value))
          (Json.record_attributes record)
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
    match Ox.Channel.try_send t.queue (Item item) with
    | Ok () -> ()
    | Error `Full -> t.dropped <- t.dropped + 1
    | Error (`Done | `Error ()) -> ()

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
    Ox_http.Client.request t.http_client ~method_:"POST" ~url
      ~headers:(("content-type", "application/json") :: t.headers)
      ~body:(Bytes.of_string body) ?deadline:t.request_deadline ~max_body_bytes:65536 ()
  with
  | Ok { status; _ } when status >= 200 && status < 300 -> Ok ()
  | Ok { status; _ } -> Error (`Status status)
  | Error error ->
      (* ^notel-nf92: callbacks may inspect the typed error, not only [pp_error].
         Keep classifiers and status, but no header values or peer-supplied text. *)
      let reason = function
        | `Malformed _ -> `Malformed "malformed collector body"
        | `Tls _ -> `Tls "TLS failed"
        | `Connect _ -> `Connect "transport failed"
        | (`Truncated | `Too_large | `Idle_timeout | `Timeout | `Closed) as reason ->
            reason
      in
      let sanitized =
        match error with
        | `Connect _ -> `Connect "transport failed"
        | `Tls _ -> `Tls "TLS failed"
        | `Protocol _ -> `Protocol "invalid HTTP exchange"
        | `Body failure ->
            `Body { failure with headers = []; reason = reason failure.reason }
        | (`Timeout | `Idle_timeout | `Closed) as error -> error
      in
      Error (`Http sanitized)

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

(* Error hooks are summaries, not a second teardown owner. A hook that parks is
   cancelled after yielding; normal nonparking callbacks and their defects remain
   independent. Record failure before calling either hook. ^notel-d52a ^notel-nf92 *)
let callback f =
  Eio.Fiber.first
    (fun () -> try f () with Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
    Eio.Fiber.yield

let note t signal = function
  | Ok () -> ()
  | Error error ->
      if t.first_failure = None then t.first_failure <- Some error;
      callback (fun () -> t.on_error error);
      callback (fun () -> t.on_signal_error signal error)

let settled t =
  let result = match t.first_failure with None -> Ok () | Some error -> Error error in
  t.first_failure <- None;
  result

let settle_control t control result =
  t.controls <- List.filter (fun other -> other != control) t.controls;
  Eio.Promise.resolve control.resolve result

let settle_controls t result =
  let controls = t.controls in
  t.controls <- [];
  List.iter
    (fun (control : control) -> Eio.Promise.resolve control.resolve result)
    controls

let send_metrics t rows =
  if rows = [] then Ok ()
  else
    post t ~url:t.metrics_url
      (Json.encode_metrics_request ~resource_attrs:t.resource_attrs
         ~scope_name:t.scope_name rows)

let export_metrics t =
  let send_window rows =
    if rows <> [] then begin
      t.pending_metric_rows <- Some rows;
      let result = send_metrics t rows in
      (* Confirmed completion is committed before a callback can suspend. *)
      t.pending_metric_rows <- None;
      note t Metrics result
    end
  in
  Option.iter send_window t.pending_metric_rows;
  send_window (Metric_aggregation.drain t.metrics)

(* Move recovery into exporter-owned storage before any suspension. The active
   Flush remains in [controls] even after it left the queue. ^notel-hjd5 ^notel-opp7 *)
let recover t =
  let items = ref (List.rev t.in_flight) in
  let take = function Item item -> items := item :: !items | Flush _ | End -> () in
  t.in_flight <- [];
  Option.iter take t.pending;
  t.pending <- None;
  let rec collect () =
    match Ox.Channel.try_receive t.queue with
    | Ok command ->
        take command;
        collect ()
    | Error (`Empty | `Done | `Error ()) -> ()
  in
  collect ();
  t.recovering <- t.recovering @ List.rev !items

let drain t =
  recover t;
  let rec batches () =
    match t.recovering with
    | [] -> ()
    | first :: rest ->
        let rec take count reversed = function
          | next :: rest when count < t.batch_size && same_signal first next ->
              take (count + 1) (next :: reversed) rest
          | rest -> (List.rev reversed, rest)
        in
        let batch, rest = take 1 [ first ] rest in
        let result = send t batch in
        t.recovering <- rest;
        note t (match first with Log _ -> Logs | Span _ -> Traces) result;
        batches ()
  in
  batches ();
  export_metrics t;
  settled t

let begin_ending t =
  match t.ending.started_at with
  | Some started_at -> started_at
  | None ->
      (* Non-suspending sealing also wakes all pre-seal admission waiters. Stop is
         channel closure, so no caller must park while trying to enqueue it. *)
      (* ^safe-p9cw ^safe-8peq: retain a native origin, not a float absolute deadline. *)
      let started_at = Eio.Time.Mono.now t.mono_clock in
      t.ending.started_at <- Some started_at;
      t.closed <- true;
      Ox.Channel.done_ t.queue;
      Eio.Promise.resolve t.ending.begin_ ();
      started_at

let record_ending t result =
  settle_controls t result;
  Eio.Promise.resolve t.ending.resolve result;
  result

let expire t =
  (* Join before accounting/discarding; no retired worker can send or settle again. *)
  t.retiring <- true;
  Option.iter (fun cc -> Eio.Cancel.cancel cc Eio.Time.Timeout) t.worker_cancel;
  Eio.Promise.await t.retired;
  recover t;
  let logs, spans =
    List.fold_left
      (fun (logs, spans) -> function
        | Log _ -> (logs + 1, spans) | Span _ -> (logs, spans + 1))
      (0, 0) t.recovering
  in
  let pending =
    match t.pending_metric_rows with None -> 0 | Some rows -> List.length rows
  in
  t.abandoned <-
    {
      logs;
      spans;
      metric_series = pending + List.length (Metric_aggregation.drain t.metrics);
      controls = List.length t.controls;
    };
  t.recovering <- [];
  t.pending_metric_rows <- None;
  record_ending t (Error `Drain_deadline)

let finish t =
  match Eio.Promise.peek t.ending.stop with
  | Some result -> result
  | None when t.finishing -> Eio.Promise.await t.ending.stop
  | None ->
      t.finishing <- true;
      Fun.protect
        ~finally:(fun () -> t.finishing <- false)
        (fun () ->
          let started_at = begin_ending t in
          let remaining =
            t.ending_seconds
            -. Mtime.Span.to_float_ns
                 (Mtime.span started_at (Eio.Time.Mono.now t.mono_clock))
               /. 1e9
          in
          if remaining <= 0. then expire t
          else
            try
              let result =
                Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds t.mono_clock remaining)
                  (fun () ->
                    if t.worker_done then
                      match t.worker_result with Some result -> result | None -> drain t
                    else begin
                      Eio.Promise.await t.retired;
                      match t.worker_result with Some result -> result | None -> drain t
                    end)
              in
              record_ending t result
            with Eio.Time.Timeout -> expire t)

let worker t =
  let started_at = ref (Eio.Time.Mono.now t.mono_clock) in
  let remaining () =
    t.metrics_interval_seconds
    -. Mtime.Span.to_float_ns (Mtime.span !started_at (Eio.Time.Mono.now t.mono_clock))
       /. 1e9
  in
  let wait seconds =
    match
      Eio.Time.Timeout.run (Eio.Time.Timeout.seconds t.mono_clock seconds) (fun () ->
          Ok
            (match Ox.Channel.receive t.queue with
            | Ok command -> command
            | Error (`Done | `Error ()) -> End))
    with
    | Ok command -> Some command
    | Error `Timeout -> None
  in
  let flush_window () =
    export_metrics t;
    started_at := Eio.Time.Mono.now t.mono_clock
  in
  let rec loop () =
    let command =
      match t.pending with
      | Some command ->
          t.pending <- None;
          Some command
      | None -> wait (max 0. (remaining ()))
    in
    match command with
    | Some End ->
        flush_window ();
        t.worker_result <- Some (settled t)
    | command ->
        (match command with
        | None -> ()
        | Some End -> assert false
        | Some (Flush control) ->
            flush_window ();
            settle_control t control (settled t)
        | Some (Item item) ->
            let rec gather count reversed =
              if count = t.batch_size then List.rev reversed
              else
                match Ox.Channel.try_receive t.queue with
                | Ok (Item next) when same_signal item next ->
                    gather (count + 1) (next :: reversed)
                | Ok next ->
                    t.pending <- Some next;
                    List.rev reversed
                | Error (`Empty | `Done | `Error ()) -> List.rev reversed
            in
            t.in_flight <- gather 1 [ item ];
            let result = send t t.in_flight in
            t.in_flight <- [];
            note t (match item with Log _ -> Logs | Span _ -> Traces) result);
        if remaining () <= 0. then flush_window ();
        loop ()
  in
  loop ()

let create ~caps ~sw ~clock ~mono_clock ~http_client ~endpoint ~service_name
    ~ending_budget ?(scope_name = "ox_otel") ?(resource = []) ?(headers = [])
    ?(batch_size = 64) ?(max_queue = 1024) ?(metrics_interval = Ox.Duration.seconds 60)
    ?(max_metric_series = 1024) ?request_deadline ?(on_error = fun _ -> ())
    ?(on_signal_error = fun _ _ -> ()) () =
  if batch_size < 1 || max_queue < 1 || max_metric_series < 1 then
    Error (`Invalid_config "batch_size, max_queue and max_metric_series must be positive")
  else if Ox.Duration.compare metrics_interval Ox.Duration.zero <= 0 then
    Error (`Invalid_config "metrics_interval must be positive")
  else if Ox.Duration.compare ending_budget Ox.Duration.zero <= 0 then
    Error (`Invalid_config "ending_budget must be positive")
  else if String.trim service_name = "" then
    Error (`Invalid_config "service_name must not be empty")
  else
    match Ox_http.Url.parse endpoint with
    | Error issue -> Error (`Invalid_config (Ox_http.Url.parse_error_to_string issue))
    | Ok url when Ox_http.Url.query url <> None || Ox_http.Url.fragment url <> None ->
        Error (`Invalid_config "OTLP endpoint cannot contain query or fragment")
    | Ok _ ->
        let endpoint = String.trim endpoint in
        let base =
          if String.ends_with ~suffix:"/" endpoint then
            String.sub endpoint 0 (String.length endpoint - 1)
          else endpoint
        in
        let queue = Ox.Channel.create ~capacity:max_queue () in
        let stop, resolve = Eio.Promise.create () in
        let begun, begin_ = Eio.Promise.create () in
        let retired, retire = Eio.Promise.create () in
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
            request_deadline;
            headers;
            on_error;
            on_signal_error;
            mono_clock :> Eio.Time.Mono.ty Eio.Resource.t;
            clock :> float Eio.Time.clock_ty Eio.Resource.t;
            metrics_interval_seconds = Ox.Duration.to_seconds_float metrics_interval;
            ending_seconds = Ox.Duration.to_seconds_float ending_budget;
            ids = Ox_caps.Cap_stdlib.Random.make_self_init ~caps ();
            dropped = 0;
            metrics = Metric_aggregation.create ~max_series:max_metric_series;
            pending_metric_rows = None;
            closed = false;
            worker_done = false;
            first_failure = None;
            retired;
            retire;
            worker_cancel = None;
            retiring = false;
            finishing = false;
            worker_result = None;
            ending = { stop; resolve; begun; begin_; started_at = None };
            controls = [];
            abandoned = nothing_abandoned;
            recovering = [];
            pending = None;
            in_flight = [];
          }
        in
        Eio.Fiber.fork_daemon ~sw (fun () ->
            Eio.Cancel.sub (fun cc ->
                t.worker_cancel <- Some cc;
                Fun.protect
                  ~finally:(fun () ->
                    t.worker_done <- true;
                    t.worker_cancel <- None;
                    Eio.Promise.resolve t.retire ())
                  (fun () ->
                    match worker t with
                    | () -> ()
                    | exception Eio.Cancel.Cancelled _ when t.retiring -> ()));
            `Stop_daemon);
        Eio.Fiber.fork_daemon ~sw (fun () ->
            Eio.Promise.await t.ending.begun;
            (* ^safe-xls8 ^safe-pufa: finish settles the shared terminal result. *)
            let _result =
              finish t
                [@@ox.allow
                  "ox-discarded-result: controller completion is retained in ending.stop \
                   for flush and shutdown callers"]
            in
            `Stop_daemon);
        (* ^notel-1stb: Eio cancels a switch's fibers before it runs its release hooks,
           so the daemon above is gone by the time this runs; the exporter exports the
           queue's remainder here, in the releasing fiber, instead of leaving it to a
           worker that cannot run. Registered during [create], so release hooks
           registered later — a program's own, on a Door stop — run first and the last
           records they log are still exported. *)
        Eio.Switch.on_release sw (fun () ->
            (* ^safe-xls8 ^safe-pufa: finish records the outcome; callbacks already report export failures. *)
            let _finish_result =
              (Eio.Cancel.protect (fun () -> finish t) : (unit, error) result)
                [@@ox.allow
                  "ox-discarded-result: switch release finishes the exporter; \
                   ending.stop retains the terminal failure and export callbacks report \
                   send failures"]
            in
            ());
        Ok t

(* ^notel-bez2: instruments record into the exporter's own aggregation table — one table
   per exporter, single domain — and a record that would add a series beyond
   [max_metric_series] is counted as dropped instead of growing memory without bound. *)
let meter t =
  Meter.create
    ~now_ms:(fun () -> int_of_float (Eio.Time.now t.clock *. 1000.))
    ~record:(fun point ->
      if not t.closed then
        if not (Metric_aggregation.add t.metrics point) then t.dropped <- t.dropped + 1)

let shutdown t =
  Eio.Fiber.check ();
  ignore (begin_ending t);
  (* A release-hook caller cannot wait for the cancelled controller. Protect only
     the fiber taking over unfinished recovery, never a waiter joining its owner. *)
  if t.worker_done && (not t.finishing) && not (Eio.Promise.is_resolved t.ending.stop)
  then begin
    (* ^safe-xls8 ^safe-pufa: finish settles the promise awaited below, including failures. *)
    let _finish_result : (unit, error) result =
      Eio.Cancel.protect (fun () -> finish t)
        [@@ox.allow
          "ox-discarded-result: takeover finish stores its result in ending.stop; \
           shutdown returns that same retained result below"]
    in
    ()
  end;
  Eio.Fiber.check ();
  Eio.Promise.await t.ending.stop

let flush t =
  Eio.Fiber.check ();
  if t.closed then Error `Closed
  else if t.worker_done then shutdown t
  else
    let wait, resolve = Eio.Promise.create () in
    let control = { wait; resolve } in
    match Ox.Channel.send t.queue (Flush control) with
    | Ok () ->
        t.controls <- control :: t.controls;
        Eio.Promise.await wait
    | Error (`Done | `Error ()) -> Eio.Promise.await t.ending.stop
