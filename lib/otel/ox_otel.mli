(** Caller-scoped OTLP/HTTP JSON exporter for Logger logs, completed spans and metric
    instruments. Borrowed [ox_http] client must outlive the exporter's ending — an
    explicit [shutdown] or the switch that owns the exporter. No global SDK, no telemetry
    of the exporter's own sends.

    Capabilities (^ncaps-x7z8): beyond Eio's [net] (through the borrowed client) and
    clock, trace and span IDs are drawn from a [Random.State] seeded from the system,
    which is [Ox_caps.Cap.random]. [create] accepts [caps] for Pie and inn while
    preserving the old call for grip until row 53; the uncapped fallback remains on ox's
    gate allow-list. ^ncaps-21nk *)

module Meter : module type of Meter
(** The instruments a program records through: a counter, an up-down counter and a
    histogram, recorded in direct style from any fiber of the exporter's domain.
    ^notel-bez2 *)

module Metric_aggregation : module type of Metric_aggregation
(** Pure aggregation of recorded points into the rows the metrics encoder writes. *)

module Otlp_json : module type of Otlp_json

type t

type error =
  [ `Invalid_config of string
  | `Http of Ox_http.Client.error
  | `Status of int
  | `Closed
  | `Drain_deadline ]

val pp_error : Format.formatter -> error -> unit

(** The OTLP pipeline whose export request failed. ^notel-na2w *)
type signal = Logs | Traces | Metrics

val create :
  ?caps:< Ox_caps.Cap.random ; .. > ->
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  http_client:Ox_http.Client.t ->
  endpoint:string ->
  service_name:string ->
  ?scope_name:string ->
  ?resource:(string * string) list ->
  ?headers:(string * string) list ->
  ?batch_size:int ->
  ?max_queue:int ->
  ?metrics_interval:Ox.Duration.t ->
  ?max_metric_series:int ->
  ?request_deadline:Ox.Duration.t ->
  ?on_error:(error -> unit) ->
  ?on_signal_error:(signal -> error -> unit) ->
  unit ->
  (t, error) result
(** Creates a daemon worker under the caller's switch; an endpoint may include a path
    prefix, to which [/v1/logs], [/v1/traces] and [/v1/metrics] are appended. The supplied
    client remains caller-owned, and must outlive the worker it feeds. ^notel-j9vc

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
    else. ^notel-6o5v

    [metrics_interval] is how often the exporter posts the window the {!meter} instruments
    have recorded, to [/v1/metrics] of the same endpoint with the same resource attributes
    and headers — sixty seconds by default. The window is also posted by {!flush}, by
    {!shutdown} and when the switch ends, in the releasing fiber, so the measurements
    taken before a stop reach the collector. A worker the switch cancelled had its window
    re-sent by that release rather than lost, at the cost of one duplicate window; a
    window a collector refused is reported through [on_error], [on_signal_error] and
    {!flush}/{!shutdown} and is not retried. ^notel-8ixo

    [on_signal_error] names the failed OTLP pipeline for each failed export batch;
    [on_error] retains its existing error-only contract. Both callbacks are invoked
    independently when supplied, including during a release drain. ^notel-na2w

    [max_metric_series] bounds how many distinct series — a name, a kind and an attribute
    set — the exporter aggregates between exports; a record that would begin one more is
    dropped and counted by {!dropped}, because attribute cardinality a program does not
    control must not grow memory without bound. ^notel-8ixo *)

val meter : t -> Meter.t
(** The exporter's meter. Instruments created from it record in direct style from any
    fiber of the exporter's domain: each measurement is aggregated into its series as it
    is recorded, so a full log or trace queue never costs a measurement, and the window is
    posted on [metrics_interval], by {!flush}, by {!shutdown} and when the switch ends.
    Recording never suspends and never blocks on collector I/O. ^notel-bez2 ^notel-8ixo *)

val reporter : t -> Ox_observability.Logger.Reporter.t
(** Accepts Logger records without JSON round-tripping. [span] start records are internal;
    their completed end records become OTLP spans when they carry IDs. The emitter never
    blocks on collector I/O; a full queue drops the newest item. ^notel-6m2q ^notel-p4xe
*)

val span_ids : t -> unit -> string
(** A 32-digit hexadecimal correlation ID generator, suitable for
    [Logger.create ~span_ids:(Ox_otel.span_ids exporter)]. Uses a private
    [Random.State.make_self_init] state: IDs are not secrets or credentials. *)

val dropped : t -> int
(** Number of records rejected when the bounded queue was full, and metric records
    rejected when the exporter already held [max_metric_series] series. *)

val flush : t -> (unit, error) result
(** Settles all earlier admitted records and returns the first send failure since the
    previous flush. It never waits for a worker the switch has already cancelled: with the
    worker gone the remaining queue is settled in the calling fiber. ^notel-p4xe
    ^notel-t8br ^notel-1stb *)

val shutdown : ?timeout:Ox.Duration.t -> t -> (unit, error) result
(** Seals admission and ends the exporter, returning the ending's result: a live worker
    drains the remaining queue and reports it, and a worker the switch has already
    cancelled is replaced by the caller's own drain rather than waited for — so a
    [shutdown] registered with [Eio.Switch.on_release] returns instead of blocking on a
    fiber that cannot run, and one called after release returns the result the release
    recorded. Repeated calls return the same result. A timeout reports [Drain_deadline],
    not a successful drain. ^notel-j9vc ^notel-t8br ^notel-1stb *)
