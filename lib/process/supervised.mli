(** Restart children according to a pure Ox schedule. The worker is an owner-switch
    daemon: cancellation and [stop] interrupt backoff and await the current child's
    protected TERM/grace/KILL finalizer before returning. No process is launched after
    [stop] returns. *)

type 'e reason = [ `Spawn of 'e | `Schedule_exhausted of Child.exit ]

type 'e event =
  | Started of int
  | Exited of int * Child.exit
  | Gave_up of 'e reason Ox.Cause.t
  | Stopped

type 'e t

val start :
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  schedule:(Child.exit, 'output) Ox.Schedule.t ->
  spawn:(sw:Eio.Switch.t -> (Child.t, 'e) result) ->
  'e t
(** Starts asynchronously; successful spawns increment the generation from zero. A typed
    spawn error stops and emits [Gave_up (Fail (Spawn e))]; schedule exhaustion emits
    [Gave_up (Fail (Schedule_exhausted exit))]. Defects are emitted as
    [Gave_up (Die ...)]. A jittered [schedule] is not seeded here: stepping one raises
    [Invalid_argument]. Pass a schedule that does not draw. *)

val generation : 'e t -> int

val events : 'e t -> 'e event Eio.Stream.t
(** Bounded to 32 events. Overflow drops the oldest event, never blocks the process
    worker, and increments [dropped]. Taking an empty stream suspends and observes
    cancellation; taking an event runs no finalizer. [Stopped] is delivered exactly once,
    last, after either [stop] or [Gave_up]; stop reading at [Stopped]. *)

val dropped : 'e t -> int

val stop : 'e t -> unit
(** Idempotent, cancellation-protected, joins worker and child finalizers. Terminal
    [Stopped] is enqueued before this returns. *)
