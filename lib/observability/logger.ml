type level = Debug | Info | Warn | Error

let rank = function Debug -> 0 | Info -> 1 | Warn -> 2 | Error -> 3

let level_to_string = function
  | Debug -> "debug"
  | Info -> "info"
  | Warn -> "warn"
  | Error -> "error"

let pp_level fmt level = Format.pp_print_string fmt (level_to_string level)

type value =
  | String of string
  | Int of int
  | Float of float
  | Bool of bool
  | Json of Eta_json.t
  | Redacted of Redact.t

let value_to_string = function
  | String value -> value
  | Int value -> string_of_int value
  | Float value -> Printf.sprintf "%g" value
  | Bool value -> string_of_bool value
  | Json value -> Eta_json.to_string value
  | Redacted value -> Redact.to_string value

let pp_value fmt value = Format.pp_print_string fmt (value_to_string value)

let value_to_json = function
  | String value -> Eta_json.string value
  | Int value -> Eta_json.int value
  | Float value -> (
      match Eta_json.float value with
      | Some json -> json
      | None -> Eta_json.string (Printf.sprintf "%g" value))
  | Bool value -> Eta_json.bool value
  | Json value -> value
  | Redacted value -> Redact.to_json value

type record = {
  ts : float;
  level : level;
  service : string;
  msg : string;
  fields : (string * value) list;
  context : (string * string) list;
}

(* Epoch milliseconds to an ISO 8601 UTC timestamp. The conversion is Howard
   Hinnant's civil_from_days: pure integer arithmetic, so the journal's clock
   reading never depends on the host's calendar or time zone (and this package
   keeps no dependency on Unix). *)
let floor_div a b =
  let quotient = a / b in
  if a mod b <> 0 && a < 0 <> (b < 0) then quotient - 1 else quotient

let iso8601_of_epoch_ms ms =
  let ms_per_day = 86_400_000 in
  let days = floor_div ms ms_per_day in
  let rest = ms - (days * ms_per_day) in
  let z = days + 719_468 in
  let era = floor_div (if z >= 0 then z else z - 146_096) 146_097 in
  let doe = z - (era * 146_097) in
  let yoe = (doe - (doe / 1_460) + (doe / 36_524) - (doe / 146_096)) / 365 in
  let y = yoe + (era * 400) in
  let doy = doe - ((365 * yoe) + (yoe / 4) - (yoe / 100)) in
  let mp = ((5 * doy) + 2) / 153 in
  let day = doy - (((153 * mp) + 2) / 5) + 1 in
  let month = mp + if mp < 10 then 3 else -9 in
  let year = y + if month <= 2 then 1 else 0 in
  let hours = rest / 3_600_000 in
  let minutes = rest mod 3_600_000 / 60_000 in
  let seconds = rest mod 60_000 / 1_000 in
  let millis = rest mod 1_000 in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" year month day hours minutes
    seconds millis

let json_object_of_fields fields =
  Eta_json.object_
    (List.map (fun (name, value) -> (name, Some (value_to_json value))) fields)

let json_object_of_context context =
  Eta_json.object_
    (List.map (fun (name, value) -> (name, Some (Eta_json.string value))) context)

let timestamp_json ts =
  let ms = int_of_float (Float.round (ts *. 1_000.)) in
  Eta_json.string (iso8601_of_epoch_ms ms)

let to_json record =
  Eta_json.object_
    [
      ("ts", Some (timestamp_json record.ts));
      ("level", Some (Eta_json.string (level_to_string record.level)));
      ("service", Some (Eta_json.string record.service));
      ("msg", Some (Eta_json.string record.msg));
      ( "fields",
        match record.fields with
        | [] -> None
        | fields -> Some (json_object_of_fields fields) );
      ( "context",
        match record.context with
        | [] -> None
        | context -> Some (json_object_of_context context) );
    ]

let to_string record = Eta_json.to_string (to_json record)

module Reporter = struct
  type t = { emit : record -> unit }

  let journal sink =
    let mutex = Eio.Mutex.create () in
    {
      emit =
        (fun record ->
          let line = to_string record ^ "\n" in
          Eio.Mutex.use_ro mutex (fun () -> Eio.Flow.copy_string line sink));
    }

  let records consume = { emit = consume }

  let writer write_line = { emit = (fun record -> write_line (to_string record ^ "\n")) }
end

module Memory = struct
  type t = { mutable kept : record list }

  let create () = { kept = [] }

  let reporter memory =
    { Reporter.emit = (fun record -> memory.kept <- record :: memory.kept) }

  let records memory = List.rev memory.kept

  let matches ?level ?field record =
    (match level with None -> true | Some level -> record.level = level)
    &&
    match field with
    | None -> true
    | Some (name, expected) -> (
        match List.assoc_opt name record.fields with
        | Some value -> String.equal (value_to_string value) expected
        | None -> false)

  let find ?level ?field memory = List.filter (matches ?level ?field) (records memory)
end

type limit = { max : int; window : Eta.Duration.t }

let limit ~max ~window =
  if max < 1 then invalid_arg "Eta_observability.Logger.limit: max must be at least 1";
  if Eta.Duration.to_ms window <= 0 then
    invalid_arg "Eta_observability.Logger.limit: window must be positive";
  { max; window }

type window_state = { mutable window_start : Mtime.t; mutable window_count : int }

type t = {
  service : string;
  min_level : level;
  base_fields : (string * value) list;
  reporter : Reporter.t;
  span_ids : (unit -> string) option;
  now : unit -> float;
  mono_now : unit -> Mtime.t;
  windows : (string, window_state) Hashtbl.t;
}

let sort_by_name pairs =
  List.sort (fun (left, _) (right, _) -> String.compare left right) pairs

let merge_fields ~base ~fields =
  let table = Hashtbl.create 16 in
  List.iter (fun (name, value) -> Hashtbl.replace table name value) base;
  List.iter (fun (name, value) -> Hashtbl.replace table name value) fields;
  Hashtbl.fold (fun name value acc -> (name, value) :: acc) table [] |> sort_by_name

let create ?(level = Info) ?(fields = []) ?span_ids ~service ~clock ~mono_clock ~reporter () =
  {
    service;
    min_level = level;
    base_fields = fields;
    reporter;
    span_ids;
    now = (fun () -> Eio.Time.now clock);
    mono_now = (fun () -> Eio.Time.Mono.now mono_clock);
    windows = Hashtbl.create 8;
  }

let enabled t level = rank level >= rank t.min_level

let emit t level ~msg ~fields =
  let record =
    {
      ts = t.now ();
      level;
      service = t.service;
      msg;
      fields = merge_fields ~base:t.base_fields ~fields;
      context = sort_by_name (Context.fields (Context.current ()));
    }
  in
  t.reporter.Reporter.emit record

(* The minimum level is the logger's own filter: it applies to every record the
   logger writes, spans included. *)
let emit_if_enabled t level ~msg ~fields =
  if enabled t level then emit t level ~msg ~fields

let milliseconds_between start finish =
  Mtime.Span.to_float_ns (Mtime.span start finish) /. 1_000_000.

let admit t limit msg =
  match limit with
  | None -> true
  | Some { max; window } ->
      let now = t.mono_now () in
      let state =
        match Hashtbl.find_opt t.windows msg with
        | Some state -> state
        | None ->
            let state = { window_start = now; window_count = 0 } in
            Hashtbl.replace t.windows msg state;
            state
      in
      if
        milliseconds_between state.window_start now
        >= float_of_int (Eta.Duration.to_ms window)
      then begin
        state.window_start <- now;
        state.window_count <- 0
      end;
      if state.window_count < max then begin
        state.window_count <- state.window_count + 1;
        true
      end
      else false

let log t level ~msg ?(fields = []) ?limit () =
  if enabled t level && admit t limit msg then emit t level ~msg ~fields

let debug t ?fields ?limit msg = log t Debug ~msg ?fields ?limit ()
let info t ?fields ?limit msg = log t Info ~msg ?fields ?limit ()
let warn t ?fields ?limit msg = log t Warn ~msg ?fields ?limit ()
let error t ?fields ?limit msg = log t Error ~msg ?fields ?limit ()

let span t ?(level = Info) ?(fields = []) ?pp_err msg f =
  let started = t.mono_now () in
  let pp_err =
    match pp_err with
    | Some pp_err -> pp_err
    | None -> fun fmt _ -> Format.pp_print_string fmt "<error>"
  in
  let summarize cause = Format.asprintf "%a" (Eta.Cause.pp_compact pp_err) cause in
  let run () =
  emit_if_enabled t level ~msg ~fields:(("event", String "start") :: fields);
  let finish outcome exit_level extra =
    let elapsed_ms = int_of_float (milliseconds_between started (t.mono_now ())) in
    emit_if_enabled t exit_level ~msg
      ~fields:
        (("event", String "end")
        :: ("elapsed_ms", Int elapsed_ms)
        :: ("outcome", String outcome) :: (extra @ fields))
  in
  match f () with
  | Ok value ->
      finish "ok" level [];
      Ok value
  | Error error ->
      finish "failed" Error [ ("error", String (summarize (Eta.Cause.Fail error))) ];
      Error error
  | exception exn ->
      let backtrace = Printexc.get_raw_backtrace () in
      let outcome, exit_level, extra =
        match exn with
        | Eio.Cancel.Cancelled _ -> ("interrupt", level, [])
        | exn ->
            ( "defect",
              Error,
              [ ("error", String (summarize (Eta.Cause.Die (exn, backtrace)))) ] )
      in
      (* Best effort: a reporter failure must not replace the exception that is
         already propagating out of the span. *)
      (try finish outcome exit_level extra with _ -> ());
      Printexc.raise_with_backtrace exn backtrace
  in
  match t.span_ids with
  | None -> run ()
  | Some generate ->
      let valid_hex length id =
        String.length id = length
        && String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) id
      in
      let inherited = Context.fields (Context.current ()) in
      let fresh () =
        let id = generate () in
        if not (valid_hex 32 id) then
          invalid_arg "Logger.span: span_ids must yield 32 lowercase hex digits";
        id
      in
      let trace_id =
        match List.assoc_opt "trace_id" inherited with
        | Some id when valid_hex 32 id -> id
        | _ -> String.sub (fresh ()) 0 32
      in
      let parent_span_id =
        match List.assoc_opt "span_id" inherited with
        | Some id when valid_hex 16 id -> id
        | _ -> ""
      in
      let span_id = String.sub (fresh ()) 0 16 in
      Context.with_fields
        [ ("trace_id", trace_id); ("span_id", span_id);
          ("parent_span_id", parent_span_id) ]
        run
