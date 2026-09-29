(* Adapted from v1:lib/otel/otlp_json.ml, retaining its pure resource/scope
   envelope, attribute, status and ProtoJSON timestamp encoding. Metrics and
   the v1 Capabilities records are deliberately not copied. *)
type yj = Ox_json.t

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
  Ox_json.array_map
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
  Ox_json.to_string
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
                             (records_key, Ox_json.array_map encode_item items);
                           ];
                       ] );
                 ];
             ] );
       ])

let encode_traces_request ~resource_attrs ~scope_name spans =
  encode_otlp_request ~resource_attrs ~scope_name ~wrapper_key:"resourceSpans"
    ~scope_key:"scopeSpans" ~records_key:"spans" span_json spans

let severity_number = function
  | Ox_observability.Logger.Debug -> 5
  | Info -> 9
  | Warn -> 13
  | Error -> 17

let severity_text level =
  Ox_observability.Logger.level_to_string level |> String.uppercase_ascii

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
  | other -> attr_value_string (Ox_json.to_string other)

and attrs_any_json fields : yj =
  `List
    (List.map
       (fun (name, value) ->
         `Assoc [ ("key", `String name); ("value", any_value_json value) ])
       fields)

let log_json (r : Ox_observability.Logger.record) : yj =
  let trace_fields =
    List.filter_map
      (fun (name, key) ->
        Option.map (fun id -> (name, `String id)) (List.assoc_opt key r.context))
      [ ("traceId", "trace_id"); ("spanId", "span_id") ]
  in
  let attrs =
    List.map
      (fun (name, value) -> (name, Ox_observability.Logger.value_to_json value))
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

(* Metric rows: copied from v1:lib/otel/otlp_json.ml, less the gauge, frequency and
   summary encoders, which no story in row 34 pulls. *)
module Metric_aggregation = Metric_aggregation

(* ProtoJSON represents the special IEEE-754 doubles as the JSON strings "NaN",
   "Infinity" and "-Infinity"; a bare NaN/Infinity/-Infinity token is not JSON and no
   strict consumer accepts it. Every supported double result crosses this one conversion,
   while ordinary finite doubles -- including signed zero -- keep their JSON number
   encoding. Field-specific admission is deliberately not relaxed here: a value that must
   be finite (a histogram boundary) is still rejected by its own validator instead of
   being made representable on the wire. *)
let wire_double value : yj =
  match classify_float value with
  | FP_nan -> `String "NaN"
  | FP_infinite -> `String (if value > 0.0 then "Infinity" else "-Infinity")
  | FP_normal | FP_subnormal | FP_zero -> `Float value

(* Metric window timestamps are already nanoseconds in an [int], not the [int64] a span
   carries, so they use their own decimal-string conversion. *)
let ns_string n = `String (string_of_int n)

let value_field (v : Meter.number) =
  match v with
  | Int n -> ("asInt", `String (string_of_int n))
  | Float f -> ("asDouble", wire_double f)

let number_data_point_json (key : Metric_aggregation.Metric_key.t) value start_ts end_ts :
    yj =
  `Assoc
    [
      ("attributes", attrs_json key.attrs);
      ("startTimeUnixNano", ns_string start_ts);
      ("timeUnixNano", ns_string end_ts);
      value_field value;
    ]

let count_json count = `String (string_of_int count)

let[@inline always] add_min_max fields ~min ~max =
  let fields =
    match min with None -> fields | Some value -> ("min", wire_double value) :: fields
  in
  match max with None -> fields | Some value -> ("max", wire_double value) :: fields

let histogram_data_point_json (key : Metric_aggregation.Metric_key.t)
    (state : Metric_aggregation.histogram_state) start_ts end_ts =
  let fields =
    [
      ("attributes", attrs_json key.attrs);
      ("startTimeUnixNano", ns_string start_ts);
      ("timeUnixNano", ns_string end_ts);
      ("count", count_json state.count);
      ("sum", wire_double state.sum);
      ("bucketCounts", `List (List.map count_json state.bucket_counts));
      (* Explicit bounds are configuration, not samples: Meter.histogram_config admits
         only finite strictly ascending values, so a nonfinite bound cannot reach this
         encoder and is not made representable here. *)
      ( "explicitBounds",
        `List (List.map (fun bound -> `Float bound) state.explicit_bounds) );
    ]
  in
  `Assoc (add_min_max fields ~min:state.min ~max:state.max)

(* ^notel-8ixo: both counters are delta sums, so a counter and an up-down counter differ
   only in [isMonotonic]: an export window reports the increments it holds. v1 encoded the
   non-monotonic counter as a cumulative value because its meter callers passed running
   totals; row 34's instruments add deltas, and an up-down counter that adds [-1] must not
   report [-1] as its total. *)
let metric_json (key : Metric_aggregation.Metric_key.t) point : yj =
  let value, start_ts, end_ts = point in
  let body : yj =
    match (key.kind, value) with
    | Meter.Counter { monotonic }, Metric_aggregation.Sum value ->
        `Assoc
          [
            ("dataPoints", `List [ number_data_point_json key value start_ts end_ts ]);
            ("aggregationTemporality", `Int 1);
            ("isMonotonic", `Bool monotonic);
          ]
    | Histogram _, Metric_aggregation.Histogram state ->
        `Assoc
          [
            ("dataPoints", `List [ histogram_data_point_json key state start_ts end_ts ]);
            ("aggregationTemporality", `Int 1);
          ]
    | _ -> invalid_arg "Ox_otel.Otlp_json.metric_json: metric kind/value mismatch"
  in
  let kind_field =
    match key.kind with Meter.Counter _ -> "sum" | Histogram _ -> "histogram"
  in
  `Assoc
    [
      ("name", `String key.name);
      ("description", `String key.description);
      ("unit", `String key.unit_);
      (kind_field, body);
    ]

let encode_metrics_request ~resource_attrs ~scope_name rows =
  encode_otlp_request ~resource_attrs ~scope_name ~wrapper_key:"resourceMetrics"
    ~scope_key:"scopeMetrics" ~records_key:"metrics"
    (fun (key, point) -> metric_json key point)
    rows
