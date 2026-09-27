(** Pure OTLP/HTTP JSON encoding of traces and logs, adapted from
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
  Eta_observability.Logger.record list ->
  string
