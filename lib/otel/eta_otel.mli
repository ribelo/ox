(** Caller-scoped OTLP/HTTP JSON exporter for Logger logs and completed spans. Borrowed
    [eta_http] client must outlive the exporter's ending — an explicit [shutdown] or the
    switch that owns the exporter. No metrics or global SDK. *)

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
  ?resource:(string * string) list ->
  ?headers:(string * string) list ->
  ?batch_size:int ->
  ?max_queue:int ->
  ?request_deadline:Eta.Duration.t ->
  ?on_error:(error -> unit) ->
  unit ->
  (t, error) result
(** Creates a daemon worker under the caller's switch; an endpoint may include a path
    prefix, to which [/v1/logs] and [/v1/traces] are appended. The supplied client remains
    caller-owned, and must outlive the worker it feeds. ^notel-j9vc

    The exporter also registers its own release hook on [sw], so pending records are
    exported when the switch ends even if nobody calls {!shutdown}: Eio cancels the
    switch's fibers before it runs its release hooks, so the daemon is already gone and
    the exporter exports what the queue still holds in the releasing fiber, under
    [Eio.Cancel.protect], at the configured [request_deadline]. Release hooks registered
    after [create] run first (releases are LIFO), so a program that logs while the switch
    is stopping still gets its last records exported. A Door SIGTERM stop releases the
    root switch this way. ^notel-1stb

    [resource] adds OTLP resource attributes to every export beside the exporter's own
    [service.name]: [service.version], [deployment.environment], a host or a build id, so
    telemetry from different builds is distinguishable. An attribute named [service.name]
    in [resource] is ignored — the exporter's [service_name] is the resource's identity.
    ^notel-jzdm

    [headers] accompany every export request, after the exporter's own [content-type] —
    the collector's API key, a tenant, an organization. Their values are never logged and
    never rendered in an error: this exporter writes no records and its {!error} values
    carry no request details, so a secret passed here reaches the collector and nothing
    else. ^notel-6o5v *)

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
    previous flush. It never waits for a worker the switch has already cancelled: with the
    worker gone the remaining queue is settled in the calling fiber. ^notel-p4xe
    ^notel-t8br ^notel-1stb *)

val shutdown : ?timeout:Eta.Duration.t -> t -> (unit, error) result
(** Seals admission and ends the exporter, returning the ending's result: a live worker
    drains the remaining queue and reports it, and a worker the switch has already
    cancelled is replaced by the caller's own drain rather than waited for — so a
    [shutdown] registered with [Eio.Switch.on_release] returns instead of blocking on a
    fiber that cannot run, and one called after release returns the result the release
    recorded. Repeated calls return the same result. A timeout reports [Drain_deadline],
    not a successful drain. ^notel-j9vc ^notel-t8br ^notel-1stb *)
