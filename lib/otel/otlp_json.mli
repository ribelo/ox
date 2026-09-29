(** Pure OTLP/HTTP JSON encoding of traces, logs and metrics, adapted from
    [v1:lib/otel/otlp_json.ml]. No Eio effects or resources are used. *)

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

val unix_ns : float -> int64
(** Saturating conversion from Unix seconds to OTLP nanoseconds. *)

val encode_traces_request :
  resource_attrs:(string * string) list -> scope_name:string -> span list -> string

val encode_logs_request :
  resource_attrs:(string * string) list ->
  scope_name:string ->
  Ox_observability.Logger.record list ->
  string

val encode_metrics_request :
  resource_attrs:(string * string) list ->
  scope_name:string ->
  Metric_aggregation.row list ->
  string
(** [encode_metrics_request ~resource_attrs ~scope_name rows] is the OTLP/HTTP JSON body
    of one metrics export: the [resourceMetrics]/[scopeMetrics]/[metrics] envelope with
    one metric per aggregated row, integer values as decimal strings, integer timestamps
    as decimal nanosecond strings, and the ProtoJSON spellings of the special doubles. An
    empty [rows] encodes a body with no metrics; the caller does not send one. ^notel-8ixo
*)
