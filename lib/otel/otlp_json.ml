(* Adapted from v1:lib/otel/otlp_json.ml, retaining its pure resource/scope
   envelope, attribute, status and ProtoJSON timestamp encoding. Metrics and
   the v1 Capabilities records are deliberately not copied. *)
type yj = Eta_json.t

type span = {
  trace_id : string;
  span_id : string;
  parent_span_id : string option;
  name : string;
  start_unix_ns : int64;
  end_unix_ns : int64;
  attrs : (string * string) list;
  status_code : int;
  status_message : string;
}

let attr_value_string s : yj = `Assoc [ ("stringValue", `String s) ]

let attrs_json (attrs : (string * string) list) : yj =
  Eta_json.array_map
    (fun (k, v) -> `Assoc [ ("key", `String k); ("value", attr_value_string v) ])
    attrs

let str_int n = `String (Int64.to_string n)

let status_json code message : yj option =
  if code = 0 then None
  else if message = "" then Some (`Assoc [ ("code", `Int code) ])
  else Some (`Assoc [ ("code", `Int code); ("message", `String message) ])

let span_json (s : span) : yj =
  let fields =
    match status_json s.status_code s.status_message with
    | None -> []
    | Some json -> [ ("status", json) ]
  in
  let fields =
    ("attributes", attrs_json s.attrs)
    :: ("endTimeUnixNano", str_int s.end_unix_ns)
    :: ("startTimeUnixNano", str_int s.start_unix_ns)
    :: ("kind", `Int 1)
    :: ("name", `String s.name)
    :: fields
  in
  let fields =
    match s.parent_span_id with
    | Some id -> ("parentSpanId", `String id) :: fields
    | None -> fields
  in
  `Assoc (("traceId", `String s.trace_id) :: ("spanId", `String s.span_id) :: fields)

let resource_json resource_attrs : yj =
  `Assoc [ ("attributes", attrs_json resource_attrs) ]

let scope_json scope_name : yj = `Assoc [ ("name", `String scope_name) ]

let encode_otlp_request ~resource_attrs ~scope_name ~wrapper_key ~scope_key ~records_key
    encode_item items =
  Eta_json.to_string
    (`Assoc
       [
         ( wrapper_key,
           `List
             [
               `Assoc
                 [
                   ("resource", resource_json resource_attrs);
                   ( scope_key,
                     `List
                       [
                         `Assoc
                           [
                             ("scope", scope_json scope_name);
                             (records_key, Eta_json.array_map encode_item items);
                           ];
                       ] );
                 ];
             ] );
       ])

let encode_traces_request ~resource_attrs ~scope_name spans =
  encode_otlp_request ~resource_attrs ~scope_name ~wrapper_key:"resourceSpans"
    ~scope_key:"scopeSpans" ~records_key:"spans" span_json spans

let severity_number = function
  | Eta_observability.Logger.Debug -> 5
  | Info -> 9
  | Warn -> 13
  | Error -> 17

let severity_text level =
  Eta_observability.Logger.level_to_string level |> String.uppercase_ascii

let unix_ns seconds =
  let ns = seconds *. 1_000_000_000. in
  if not (Float.is_finite ns) then 0L
  else if ns >= Int64.to_float Int64.max_int then Int64.max_int
  else if ns <= Int64.to_float Int64.min_int then Int64.min_int
  else Int64.of_float ns

let rec any_value_json (value : yj) : yj =
  match value with
  | `String s -> `Assoc [ ("stringValue", `String s) ]
  | `Bool b -> `Assoc [ ("boolValue", `Bool b) ]
  | `Int n -> `Assoc [ ("intValue", `String (string_of_int n)) ]
  | `Intlit n -> `Assoc [ ("intValue", `String n) ]
  | `Float n -> `Assoc [ ("doubleValue", `Float n) ]
  | `List values ->
      `Assoc
        [ ("arrayValue", `Assoc [ ("values", `List (List.map any_value_json values)) ]) ]
  | `Assoc fields ->
      `Assoc [ ("kvlistValue", `Assoc [ ("values", attrs_any_json fields) ]) ]
  | `Null -> `Assoc [ ("stringValue", `String "null") ]
  | other -> attr_value_string (Eta_json.to_string other)

and attrs_any_json fields : yj =
  `List
    (List.map
       (fun (name, value) ->
         `Assoc [ ("key", `String name); ("value", any_value_json value) ])
       fields)

let log_json (r : Eta_observability.Logger.record) : yj =
  let trace_fields =
    List.filter_map
      (fun (name, key) ->
        Option.map (fun id -> (name, `String id)) (List.assoc_opt key r.context))
      [ ("traceId", "trace_id"); ("spanId", "span_id") ]
  in
  let attrs =
    List.map
      (fun (name, value) -> (name, Eta_observability.Logger.value_to_json value))
      r.fields
    @ List.map
        (fun (name, value) -> (name, `String value))
        (List.filter
           (fun (name, _) ->
             name <> "trace_id" && name <> "span_id" && name <> "parent_span_id")
           r.context)
  in
  `Assoc
    (("timeUnixNano", str_int (unix_ns r.ts))
    :: ("observedTimeUnixNano", str_int (unix_ns r.ts))
    :: ("severityNumber", `Int (severity_number r.level))
    :: ("severityText", `String (severity_text r.level))
    :: ("body", attr_value_string r.msg)
    :: ("attributes", attrs_any_json attrs)
    :: trace_fields)

let encode_logs_request ~resource_attrs ~scope_name records =
  encode_otlp_request ~resource_attrs ~scope_name ~wrapper_key:"resourceLogs"
    ~scope_key:"scopeLogs" ~records_key:"logRecords" log_json records
