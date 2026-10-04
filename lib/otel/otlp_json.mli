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

val record_attributes :
  Ox_observability.Logger.record -> (string * Ox_observability.Logger.value) list
(** [record_attributes record] is the business attributes an exported log or span carries:
    the record's inherited context first, as strings, then its explicit fields, with
    exactly one entry per key and the explicit field winning a duplicate. The trace
    controls [trace_id], [span_id] and [parent_span_id] are never attributes, from either
    side; they become native OTLP IDs instead. {!Ox_observability.Logger.Redacted} values
    stay redacted: they are serialized as ["<redacted>"]. ^notel-nbvl ^notel-uydw
    ^notel-p11y ^notel-dzpj *)

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
