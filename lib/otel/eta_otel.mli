(** Caller-scoped OTLP/HTTP JSON exporter for Logger logs and completed spans. Borrowed
    [eta_http] client must outlive [shutdown]. No metrics or global SDK. *)

module Otlp_json : module type of Otlp_json

type t

type error =
  [ `Invalid_config of string
  | `Http of Eta_http.Client.error
  | `Status of int
  | `Closed
  | `Drain_deadline ]

val pp_error : Format.formatter -> error -> unit

val create :
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  http_client:Eta_http.Client.t ->
  endpoint:string ->
  service_name:string ->
  ?scope_name:string ->
  ?batch_size:int ->
  ?max_queue:int ->
  ?request_deadline:Eta.Duration.t ->
  ?on_error:(error -> unit) ->
  unit ->
  (t, error) result
(** Creates a daemon worker under the caller's switch; an endpoint may include a path
    prefix, to which [/v1/logs] and [/v1/traces] are appended. The supplied client remains
    caller-owned. Explicitly [shutdown] before releasing it. ^notel-j9vc *)

val reporter : t -> Eta_observability.Logger.Reporter.t
(** Accepts Logger records without JSON round-tripping. [span] start records are internal;
    their completed end records become OTLP spans when they carry IDs. The emitter never
    blocks on collector I/O; a full queue drops the newest item. ^notel-6m2q ^notel-p4xe
*)

val span_ids : t -> unit -> string
(** A 32-digit hexadecimal correlation ID generator, suitable for
    [Logger.create ~span_ids:(Eta_otel.span_ids exporter)]. Uses a private
    [Random.State.make_self_init] state: IDs are not secrets or credentials. *)

val dropped : t -> int
(** Number of records rejected when the bounded queue was full. *)

val flush : t -> (unit, error) result
(** Settles all earlier admitted records and returns the first send failure since the
    previous flush. ^notel-p4xe ^notel-t8br *)

val shutdown : ?timeout:Eta.Duration.t -> t -> (unit, error) result
(** Seals admission and waits for the worker to finish. Repeated calls return the same
    result. A timeout reports [Drain_deadline], not a successful drain; the worker remains
    owned by the caller's switch until it finishes or is cancelled. ^notel-j9vc
    ^notel-t8br *)
