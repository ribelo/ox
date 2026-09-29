(** Restartable child scopes under a caller's scope, after OTP's supervisor and Riot's
    `Supervisor`, in Eio's terms (^nactor-d120). A supervisor is an opt-in restart
    boundary, not a new cancellation system: it has no detached start, no process links or
    monitors, and no runtime. Everything it owns lives on the scope the caller passes, and
    ends with it.

    {2 Children}

    A child is a stable id, a fresh-start function, a restart type, a shutdown mode and
    significance. Each incarnation runs the start function inside its own
    {!Scope.run}[ (]{!Scope.supervised_error}[)]: resources are acquired on the child's
    own switch ({!Scope.switch} of {!context.scope}), and a completion is published to the
    supervisor only after that scope has released them. Start functions create fresh state
    and resources — never reuse a stopped {!Actor} or {!Agent} handle — and must run for
    the child's whole lifetime: returning means the child completed. An actor child
    creates its actor on the context's switch, publishes the handle, calls [ready] and
    waits for [stop_requested].

    {2 Readiness and replacement handles}

    {!start} returns once every static child has called [context.ready] (or completed
    normally before doing so), in specification order. A child that fails before it is
    ready ends the start with [`Start_failed] after the started children were stopped in
    reverse order; initial starts never consume the restart budget. During recovery the
    same handshake orders a restart batch: the next child is started only when the
    previous one is ready, so dependents come up after what they need.

    There is no registry. A replacement's handle is republished by the child itself
    through an {!Agent} created on the {e outer} switch:
    [Agent.update registry (fun _ -> Some actor)] before [ready ()]. Dependents read the
    agent at the point of use, so they always see the current incarnation.

    {2 Classification}

    The supervisor is a classification boundary like {!Scope.run}: a child's typed
    [Error e] is [Cause.Fail e]; a non-cancellation exception is
    [Cause.Die (exn, backtrace)], reported through [on_event] with the original exception
    and backtrace, and eligible for restart; a failing cleanup stays in the full child
    {!Cause.t} (and, by {!Scope.supervised_error}'s rule that a defect wins over a typed
    failure, a cleanup defect is then what that Cause holds). Cancellation is never a
    defect and never a typed failure: external cancellation of the owning scope cancels
    and awaits every child, never triggers recovery, and propagates with its identity. A
    stop the supervisor itself requested is marked before the cancellation; its
    interruption is not a failure event. A {e cleanup defect} during a requested stop is
    still reported: it is raised, unchanged, from the supervisor's fiber once every child
    has been joined (so it ends the owning scope as a defect), never discarded as an
    expected interruption. Ordinary combinators still re-raise defects unchanged; this
    boundary is explicit.

    {2 Strategies, restart types, intensity}

    Restart eligibility is tested on the child that exited: [Permanent] restarts on any
    exit, [Temporary] never, [Transient] on typed failure or defect but not on normal
    completion. [One_for_one] recovers only the eligible child; [One_for_all] stops every
    active child (reverse specification order, each joined) then restarts the failed child
    and the restartable others in specification order; [Rest_for_one] does the same for
    the failed child and the active children after it. A collateral [Temporary] is stopped
    and removed; a collateral [Transient] is restarted; a child that already completed
    normally is never revived. Induced stops never start another recovery and are not
    exits. Exits that are already complete when a recovery begins are part of that one
    recovery.

    The budget is [{ max_restarts; window }] over the supplied clock: one recovery batch
    is one attempt however many children it restarts, a restarted incarnation that fails
    and needs another recovery is another attempt, and the window is half-open — attempts
    at or before [now - window] are forgotten. Before the attempt that would exceed the
    budget every child is stopped and joined, then the supervisor ends with
    [`Restart_intensity_exceeded]. [max_restarts = 0] disables automatic restart.

    {2 Shutdown}

    Shutdown is cooperative and never a kill. [Infinity] resolves [stop_requested] and
    waits for the child with no local deadline; [Timeout d] resolves it, waits at most [d]
    on the supplied clock ({!Timeout.timeout}), then cancels the child's cancellation
    context and still waits for its finalizers; [Brutal_kill] skips the grace signal and
    cancels at once, still running finalizers and joining. Eio cannot kill a fiber, skip
    its finalizers, or bound cancellation-protected cleanup: a child that ignores the
    signal, or a finalizer that blocks, delays the join. Cancellation of the owning scope
    takes precedence over every graceful mode. *)

type restart = Permanent | Temporary | Transient

type shutdown =
  | Brutal_kill  (** cancel at once; finalizers still run and are joined *)
  | Timeout of Duration.t
      (** grace signal, deadline on the clock, then cancel and join *)
  | Infinity  (** grace signal, no local deadline *)

type strategy = One_for_one | One_for_all | Rest_for_one

type auto_shutdown =
  | Never
  | Any_significant  (** stop at the first significant child's terminal exit *)
  | All_significant  (** stop when every significant child has had its terminal exit *)

type intensity = { max_restarts : int; window : Duration.t }

type 'e context = {
  scope : 'e Scope.t;
      (** the incarnation's own scope: fork typed work with {!Scope.fork_error} and
          register releases on {!Scope.switch} *)
  stop_requested : unit Eio.Promise.t;
      (** resolved when the supervisor asks this incarnation to stop gracefully; the child
          should then end normally *)
  incarnation : int;  (** 1 for the first start, counting up *)
  ready : unit -> unit;  (** the child is up; idempotent *)
}

type 'e child

val child :
  id:string ->
  ?restart:restart ->
  ?shutdown:shutdown ->
  ?significant:bool ->
  ('e context -> (unit, 'e) result) ->
  'e child
(** [child ~id start] describes a child. Defaults: [Permanent], [Timeout] of five seconds,
    not significant. Only [Temporary] and [Transient] children may be significant; that is
    checked by {!start}. *)

type ('input, 'e) template

val template :
  id:string ->
  ?restart:restart ->
  ?shutdown:shutdown ->
  ('input -> 'e context -> (unit, 'e) result) ->
  ('input, 'e) template
(** The one template of a {!start_simple} supervisor; instances get their [input]. *)

type 'e event =
  | Child_started of { child_id : string; incarnation : int }
  | Child_stop_requested of { child_id : string; incarnation : int; mode : shutdown }
  | Child_exited of {
      child_id : string;
      incarnation : int;
      cause : 'e Cause.t option;  (** [None] for normal completion *)
      induced : bool;  (** the supervisor had asked it to stop *)
    }
  | Restart_attempt of { child_id : string; attempt : int }
      (** one recovery batch, triggered by [child_id]; [attempt] counts those in the
          window *)
  | Shutting_down of [ `Requested | `Auto_shutdown | `Restart_intensity_exceeded ]
      (** What the supervisor reports about itself. *)

type 'e intensity_error = {
  child_id : string;
      (** the child whose exit needed the attempt that exceeded the budget *)
  max_restarts : int;
  window : Duration.t;
  last_cause : 'e Cause.t option;
      (** its full exit cause, defect backtrace included; [None] if a [Permanent] child
          exhausted the budget by completing normally *)
}

type 'e start_failure = { failed_id : string; cause : 'e Cause.t }

type 'e outcome =
  | Stopped  (** {!stop} was called *)
  | Auto_shutdown
  | Cancelled  (** the owning scope was cancelled or ended *)
  | Intensity_exceeded of 'e intensity_error

type 'e t
(** A running supervisor. *)

val start :
  scope:([> `Restart_intensity_exceeded of 'ce intensity_error ] as 'e) Scope.t ->
  clock:_ Eio.Time.clock ->
  intensity:intensity ->
  ?auto_shutdown:auto_shutdown ->
  ?on_event:('ce event -> unit) ->
  strategy:strategy ->
  'ce child list ->
  ('ce t, [> `Invalid_supervisor of string | `Start_failed of 'ce start_failure ]) result
(** [start ~scope ~clock ~intensity ~strategy children] validates the configuration before
    starting anything ([`Invalid_supervisor] for a negative [max_restarts], a zero window,
    an empty or repeated id, or a significant [Permanent] child), then starts the children
    in order, each after the previous is ready, and returns.

    The supervisor is a daemon fork of [scope]: it ends when [scope] does, cancelling and
    joining its children, and its terminal typed failure [`Restart_intensity_exceeded]
    ends [scope] like any {!Scope.fork_error_daemon} failure — after every child was
    stopped and joined. Call {!stop} first for a graceful end. [clock] measures intensity
    windows and [Timeout] shutdowns and should be monotonic.

    [on_event] (default: {!Eio.traceln} for abnormal exits, backtraces included) receives
    every {!event} synchronously from the supervisor's fiber and must not suspend. *)

val stop : 'e t -> 'e outcome
(** Ask the supervisor to end and wait for it: every child is stopped in reverse
    specification order and joined. Idempotent; a supervisor that had already ended
    answers its outcome. *)

val await : 'e t -> 'e outcome
(** Wait for the supervisor to end, however it does (auto shutdown, intensity, {!stop}).
*)

type child_state = [ `Starting | `Running | `Restarting | `Completed ]
type child_info = { id : string; incarnation : int; state : child_state }

val children : _ t -> child_info list
(** The children in specification order as they are at this instant, read without a
    message. [`Completed] children finished without restart. Removed children are absent.
*)

val terminate_child : 'e t -> string -> (unit, [> `Unknown_child | `Stopped ]) result
(** Stop the named child by its shutdown mode, join it and remove it: it is not restarted,
    an induced stop is not a significant completion, and it leaves the significant set (an
    emptied set never auto-stops). [`Stopped] if the supervisor already ended. *)

type ('input, 'e) simple
(** A supervisor of instances of one template ([Simple_one_for_one]): it starts with no
    child, each {!start_child} adds one, a restart replaces only that instance, and its
    restart input is reused. Significance is not offered. *)

val start_simple :
  scope:([> `Restart_intensity_exceeded of 'ce intensity_error ] as 'e) Scope.t ->
  clock:_ Eio.Time.clock ->
  intensity:intensity ->
  ?on_event:('ce event -> unit) ->
  ('input, 'ce) template ->
  (('input, 'ce) simple, [> `Invalid_supervisor of string ]) result
(** As {!start}, with the same intensity, shutdown and classification rules; there is
    nothing to wait for at start. *)

val start_child :
  ('input, 'e) simple ->
  'input ->
  (string, [> `Start_failed of 'e start_failure | `Stopped ]) result
(** Start an instance from [input] and return its id once it is ready. An instance that
    fails before it is ready is not restarted and reports [`Start_failed]. *)

val supervisor : ('input, 'e) simple -> 'e t
(** The common handle: {!stop}, {!await}, {!children}, {!terminate_child}. *)
