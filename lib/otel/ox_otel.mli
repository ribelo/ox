(** Caller-scoped OTLP/HTTP JSON exporter for Logger logs, completed spans and metric
    instruments. Borrowed [ox_http] client must outlive the exporter's ending — an
    explicit [shutdown] or the switch that owns the exporter. No global SDK, no telemetry
    of the exporter's own sends.

    Capabilities (^ncaps-x7z8 ^ncaps-21nk): beyond Eio's [net] (through the borrowed
    client) and clock, trace and span IDs are drawn from a [Random.State] seeded from the
    system, which is [Ox_caps.Cap.random]. [create] requires [~caps]; there is no uncapped
    fallback. *)

module Meter : module type of Meter
(** The instruments a program records through: a counter, an up-down counter and a
    histogram, recorded in direct style from any fiber of the exporter's domain.
    ^notel-bez2 *)

module Metric_aggregation : module type of Metric_aggregation
(** Pure aggregation of recorded points into the rows the metrics encoder writes. *)

module Otlp_json : module type of Otlp_json

type t

type abandoned = { logs : int; spans : int; metric_series : int; controls : int }
(** Counts of unsent or uncertain work abandoned at expiry, not exact remote losses.
    Counts are bounded by queue plus batch capacity, one pending command and two
    metric-series windows; control counts add the one active control. *)

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
  caps:< Ox_caps.Cap.random ; .. > ->
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  http_client:Ox_http.Client.t ->
  endpoint:string ->
  service_name:string ->
  ending_budget:Ox.Duration.t ->
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
    [Eio.Cancel.protect], within [ending_budget]. This required positive finite budget
    starts at the first shutdown or owner release, and is one absolute deadline for
    sealing, all sends, recovery and control settlement. Request deadlines never extend
    it. Release hooks registered after [create] run first (LIFO), preserving last records
    logged by program cleanup and Door SIGTERM. ^notel-1stb ^notel-056b ^notel-jx0z

    Suspension: may suspend while starting the daemon fibers; delegated Ox.Channel,
    Ox.Duration, Ox_caps.Cap_stdlib, Ox_http.Client, Ox_http.Url, Ox_json,
    Ox_observability.Logger, Stdlib, Stdlib.Array, Stdlib.Bytes, Stdlib.Float,
    Stdlib.Int64, Stdlib.List, Stdlib.Option, Stdlib.String operations retain their own
    behaviour. Cancellation: depends on the owner switch; both daemons inherit its
    context; delegated Ox.Channel, Ox.Duration, Ox_caps.Cap_stdlib, Ox_http.Client,
    Ox_http.Url, Ox_json, Ox_observability.Logger, Stdlib, Stdlib.Array, Stdlib.Bytes,
    Stdlib.Float, Stdlib.Int64, Stdlib.List, Stdlib.Option, Stdlib.String operations
    retain their own behaviour. Cancellation safety: safe to re-run; successfully
    constructed exporters remain switch-owned and their ending is bounded. Finalizers: the
    owner switch bounds recovery by the same ending deadline. Locking: single-domain state
    changes hold no mutex across caller code.

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
    independently when supplied, including during a release drain. They must be nonparking
    summaries; a callback that suspends is cancelled, and callback defects are best
    effort. Failure classification survives callback cancellation. Transport error
    payloads are sanitized before callbacks or public results; collector headers/bodies
    are not retained for diagnostics. ^notel-na2w ^notel-nf92

    [max_metric_series] bounds how many distinct series — a name, a kind and an attribute
    set — the exporter aggregates between exports; a record that would begin one more is
    dropped and counted by {!dropped}, because attribute cardinality a program does not
    control must not grow memory without bound. ^notel-8ixo

    @raise Invalid_argument
      if sw is finished when the exporter daemons are started or its release hook is
      registered. ^nlintd-raises

    The exporter has an internal Assert_failure for its terminal stop-event invariant:
    Some `End is handled before the residual branch. ^nlintd-truth

    Eio.Switch.Release_error can propagate if a release callback fails on a switch owned
    by a delegated operation. ^nlintd-truth *)

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

    Logs and spans carry {!Otlp_json.record_attributes}: the fiber's inherited context and
    the record's explicit fields, one attribute per key, explicit fields winning; the
    trace controls become native IDs only. A span omits the kernel's [event], [outcome],
    [elapsed_ms] and [error], which become its status and timing. ^notel-nbvl ^notel-uydw
    ^notel-p11y ^notel-jda9 ^notel-dzpj *)

val span_ids : t -> unit -> string
(** A 32-digit hexadecimal correlation ID generator, suitable for
    [Logger.create ~span_ids:(Ox_otel.span_ids exporter)]. Draws from the private state
    {!create} seeded through [Ox_caps.Cap.random]. IDs are not secrets or credentials. *)

val dropped : t -> int
(** Number of records rejected when the bounded queue was full, and metric records
    rejected when the exporter already held [max_metric_series] series. *)

val abandoned : t -> abandoned
(** Counts retained after [Drain_deadline]; zero before expiry. Payloads are discarded,
    not retained for diagnostics or counted as ordinary queue rejection. ^notel-od2q *)

val flush : t -> (unit, error) result
(** Settles earlier admitted work and returns the first send failure since the preceding
    flush. A queued, pending or consumed control remains owned until it settles exactly
    once, including owner cancellation and metric recovery. A caller blocked on full-queue
    admission before sealing joins the terminal ending; a new caller after sealing
    receives [Closed]. ^notel-p4xe ^notel-t8br ^notel-1stb ^notel-hjd5 ^notel-d52a
    ^notel-5qi9

    Suspension: may suspend on queue capacity, collector export and settlement.
    Cancellation: propagates Eio interruption of this waiter, never corrupting shared
    state. Cancellation safety: safe to re-run; admitted controls retain their independent
    owner, although uncertain exports can be delivered at least once rather than exactly
    once. Finalizers: the exporter owner recovers and settles admitted controls within its
    budget. Locking: no mutex spans waits or error callbacks. *)

val shutdown : t -> (unit, error) result
(** Seals admission without suspension and joins one exporter-owned ending. Concurrent and
    repeated calls return the immutable terminal result. Expiry returns [Drain_deadline],
    records {!abandoned}, settles controls and retires the worker before publishing the
    result; no further HTTP send occurs after ending. A cancelled waiter never becomes a
    deadline failure or leaves an unowned transition. Release-hook callers recover
    uncertain in-flight batches at least once, within the original absolute deadline.
    There is no per-caller timeout: the required construction [ending_budget] is the sole
    ending budget. ^notel-j9vc ^notel-t8br ^notel-1stb ^notel-s12c ^notel-48tm ^notel-m8ax
    ^notel-opp7

    Suspension: may suspend awaiting the terminal ending, or recovering during owner
    release. Cancellation: propagates waiter interruption; owner-release recovery is
    protected only within the ending deadline. Cancellation safety: safe to re-run;
    callers join the same terminal result and cannot reset the deadline or lose shared
    progress. Finalizers: the owner switch retires its worker and completes bounded
    recovery. Locking: no mutex spans waits, HTTP sends or error callbacks. *)
