module Logger = Eta_observability.Logger
module Otlp_json = Otlp_json
module Json = Otlp_json

type error =
  [ `Invalid_config of string
  | `Http of Eta_http.Client.error
  | `Status of int
  | `Closed
  | `Drain_deadline ]

let pp_error ppf = function
  | `Invalid_config reason -> Format.fprintf ppf "invalid OTLP configuration: %s" reason
  | `Http _ -> Format.pp_print_string ppf "OTLP HTTP transport failed"
  | `Status status -> Format.fprintf ppf "OTLP collector returned HTTP %d" status
  | `Closed -> Format.pp_print_string ppf "OTLP exporter is closed"
  | `Drain_deadline -> Format.pp_print_string ppf "OTLP drain deadline reached"

type item = Log of Logger.record | Span of Json.span

type command =
  | Item of item
  | Flush of (unit, error) result Eio.Promise.u
  | Stop of (unit, error) result Eio.Promise.u

type t = {
  queue : command Eio.Stream.t;
  http_client : Eta_http.Client.t;
  logs_url : string;
  traces_url : string;
  resource_attrs : (string * string) list;
  scope_name : string;
  batch_size : int;
  max_queue : int;
  request_deadline : Eta.Duration.t option;
  headers : (string * string) list;
  on_error : error -> unit;
  with_timeout : float -> (unit -> (unit, error) result) -> (unit, error) result;
  ids : Random.State.t;
  mutable dropped : int;
  mutable closed : bool;
  mutable stop : (unit, error) result Eio.Promise.t option;
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

let send t items =
  match items with
  | [] -> Ok ()
  | first :: _ -> (
      let body, url =
        match first with
        | Log _ ->
            let records =
              List.filter_map (function Log r -> Some r | Span _ -> None) items
            in
            ( Json.encode_logs_request ~resource_attrs:t.resource_attrs
                ~scope_name:t.scope_name records,
              t.logs_url )
        | Span _ ->
            let spans =
              List.filter_map (function Span s -> Some s | Log _ -> None) items
            in
            ( Json.encode_traces_request ~resource_attrs:t.resource_attrs
                ~scope_name:t.scope_name spans,
              t.traces_url )
      in
      match
        Eta_http.Client.request t.http_client ~method_:"POST" ~url
          ~headers:(("content-type", "application/json") :: t.headers)
          ~body:(Bytes.of_string body) ?deadline:t.request_deadline ~max_body_bytes:0 ()
      with
      | Ok { status; _ } when status >= 200 && status < 300 -> Ok ()
      | Ok { status; _ } -> Error (`Status status)
      | Error error -> Error (`Http error))

let same_signal a b =
  match (a, b) with Log _, Log _ | Span _, Span _ -> true | _ -> false

let worker t =
  let pending = ref None in
  let first_failure = ref None in
  let note = function
    | Ok () -> ()
    | Error error -> (
        if !first_failure = None then first_failure := Some error;
        try t.on_error error with _ -> ())
  in
  let settled () =
    let result = match !first_failure with None -> Ok () | Some error -> Error error in
    first_failure := None;
    result
  in
  let rec loop () =
    let command =
      match !pending with
      | Some command ->
          pending := None;
          command
      | None -> Eio.Stream.take t.queue
    in
    match command with
    | Flush resolve ->
        Eio.Promise.resolve resolve (settled ());
        loop ()
    | Stop resolve -> Eio.Promise.resolve resolve (settled ())
    | Item item ->
        let rec gather count reversed =
          if count = t.batch_size then List.rev reversed
          else
            match Eio.Stream.take_nonblocking t.queue with
            | Some (Item next) when same_signal item next ->
                gather (count + 1) (next :: reversed)
            | Some next ->
                pending := Some next;
                List.rev reversed
            | None -> List.rev reversed
        in
        note (send t (gather 1 [ item ]));
        loop ()
  in
  loop ()

let create ~sw ~clock ~http_client ~endpoint ~service_name ?(scope_name = "eta_otel")
    ?(resource = []) ?(headers = []) ?(batch_size = 64) ?(max_queue = 1024)
    ?request_deadline ?(on_error = fun _ -> ()) () =
  if batch_size < 1 || max_queue < 1 then
    Error (`Invalid_config "batch_size and max_queue must be positive")
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
        let t =
          {
            queue = Eio.Stream.create max_queue;
            http_client;
            logs_url = base ^ "/v1/logs";
            traces_url = base ^ "/v1/traces";
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
            with_timeout = (fun seconds f -> Eio.Time.with_timeout_exn clock seconds f);
            ids = Random.State.make_self_init ();
            dropped = 0;
            closed = false;
            stop = None;
          }
        in
        Eio.Fiber.fork_daemon ~sw (fun () ->
            worker t;
            `Stop_daemon);
        Ok t

let flush t =
  if t.closed then Error `Closed
  else
    let wait, resolve = Eio.Promise.create () in
    Eio.Stream.add t.queue (Flush resolve);
    Eio.Promise.await wait

let shutdown ?timeout t =
  let wait =
    match t.stop with
    | Some wait -> wait
    | None ->
        t.closed <- true;
        let wait, resolve = Eio.Promise.create () in
        t.stop <- Some wait;
        Eio.Stream.add t.queue (Stop resolve);
        wait
  in
  match timeout with
  | None -> Eio.Promise.await wait
  | Some duration -> (
      try
        t.with_timeout (Eta.Duration.to_seconds_float duration) (fun () ->
            Eio.Promise.await wait)
      with Eio.Time.Timeout -> Error `Drain_deadline)
