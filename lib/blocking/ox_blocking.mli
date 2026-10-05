(** Cancellation and finalizers: Suspension: may suspend in Eio.Semaphore.acquire
    admission waits and Eio.Promise.await completion waits; native callbacks run through
    the worker pool; depends on delegated Eio worker/job setup and caller native
    callbacks. Cancellation: propagates Eio.Cancel.Cancelled to the waiting caller but
    does not preempt a started native callback; depends on delegated Eio worker/job checks
    and caller native callbacks. Finalizers: no hook is registered; the pool owner must
    retain callback resources until physical completion or draining shutdown. Locking:
    admission synchronization is delegated to Eio; native callbacks own their locks.
    Cancellation safety: unsafe because progress is lost for the waiting caller while a
    started callback may still complete and publish effects. ^nlintd-z5p5 ^nlintd-vneh *)

(** Direct-style bridge from Eio fibers to blocking native callbacks. Pools are owned by
    one Eio domain (worker-thread completion uses only thread-safe atomics/semaphores). A
    caller's cancellation never preempts a started callback. Do not release callback
    resources on caller cancellation: use [Pool.Drain] at the resource's owner scope
    and/or retain a separate lease until physical completion. No switch finalizers are
    registered by this package. *)

module Pool : sig
  type t
  type shutdown_policy = Drain | Detach_started

  type config = {
    max_threads : Ox.Concurrency.t;
    max_queued : int;
    shutdown_policy : shutdown_policy;
  }

  type stats = {
    active : int;
    queued : int;
    waiting : int;
    completed : int;
    rejected : int;
    cancelled_before_start : int;
    detached : int;
  }

  val create : sw:Eio.Switch.t -> ?name:string -> config -> t
  (** Raises [Invalid_argument] for negative [max_queued]. [max_threads] is a checked
      positive concurrency bound. Only [Ox.Concurrency.to_int max_threads] callbacks can
      physically run at once. [max_queued] bounds admitted waiting fibers; other [run]
      callers wait outside admission. The owner switch retains every worker fiber,
      including calls whose caller has timed out or cancelled. Shut down before releasing
      that switch. Suspension: never suspends; this call only reads or constructs OCaml
      values; numeric bounds use delegated Stdlib integer comparisons and the delegated
      [Ox.Concurrency.to_int] projection. Cancellation: not a cancellation point; this
      call performs no Eio cancellation check; numeric bounds use delegated Stdlib integer
      comparisons and the delegated [Ox.Concurrency.to_int] projection without an Eio
      check. Finalizers: none are registered by this call; existing resource ownership is
      unchanged. Locking: no lock is acquired by this call. ^nlintd-a7oq *)

  val shutdown_policy : t -> shutdown_policy
  (** Suspension: never suspends; this call only reads or constructs OCaml values.
      Cancellation: not a cancellation point; this call performs no Eio cancellation
      check. Finalizers: none are registered by this call; existing resource ownership is
      unchanged. Locking: no lock is acquired by this call. ^nlintd-a7oq *)

  val stats : t -> stats
  (** Suspension: never suspends; this call only reads or constructs OCaml values.
      Cancellation: not a cancellation point; this call performs no Eio cancellation
      check. Finalizers: none are registered by this call; existing resource ownership is
      unchanged. Locking: no lock is acquired by this call. ^nlintd-a7oq *)

  val shutdown : t -> unit
  (** Closes admission. The first call seals the pool: from then on [run] and [try_run]
      return [Shutting_down] without starting a callback, including callers that were
      already waiting for a slot. Shutdown policy is fixed at [create].

      [Drain] is one ending owned by the pool, not by its caller. Every call, concurrent
      or repeated, waits for the same completion: every callback that physically started
      has returned and its [on_settled] hook ran exactly once, including calls whose
      callers were cancelled or timed out. Repeated calls after completion return at once
      and change no accounting. If an [on_settled] hook raised after its caller was
      cancelled or timed out, the first such exception is retained for the pool's
      lifetime, and every [Drain] call raises it with its original backtrace once all
      callbacks and hooks have settled, instead of returning. A hook exception delivered
      to a still-waiting caller is not retained. [Drain] must run outside a callback using
      this pool, before the owner switch ends.

      [Detach_started] returns immediately, leaving started callbacks and their resources
      with the caller to manage; a hook exception after caller cancellation is not
      reported. Neither policy interrupts a native callback.

      Suspension: may suspend under [Drain] until every admitted call has physically
      settled; never suspends under [Detach_started]. Cancellation: propagates out of the
      [Drain] wait; a cancelled caller only stops waiting, admission stays sealed and the
      pool still completes the ending for other callers. Finalizers: none are registered;
      started callbacks stay owned by the pool's owner switch. Locking: no lock is
      acquired; the wait spans no caller code. Cancellation safety: safe to re-run because
      sealing is idempotent and a later call joins the same ending. ^nblock-5siy
      ^nblock-8z91 ^nblock-de0p ^nblock-l36w ^nblock-faq7 ^nblock-l78q *)
end

type admission_failure = Saturated | Shutting_down
type 'a try_run_outcome = Completed of 'a | Not_run of admission_failure

val run :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:(('a, exn) result -> unit) ->
  (unit -> 'a) ->
  ('a, [ `Shutting_down ]) result
(** Wait for a slot. Cancellation before worker claim prevents callback execution; after
    claim it releases the caller, invokes [on_cancel] at most once in the caller fiber,
    and keeps the slot until physical completion. The hook must not throw. Callback
    exceptions propagate with their backtrace as defects. Raises [Invalid_argument] if the
    pool owner's switch is finished or belongs to another domain when starting the worker
    fiber. This startup check is in the caller, unlike worker execution. ^nlintd-truth
    ^nlintd-raises

    [on_settled] (every [run] variant) is invoked exactly once, in the pool owner's Eio
    context (never the system thread), after the callback has physically finished, with
    its value or exception, also when the caller was cancelled or timed out long before.
    It is not invoked for a call abandoned before a worker claimed it (the callback never
    ran). It runs before a still-waiting caller sees the result and before the slot is
    released, so a [Drain] shutdown returns only after every [on_settled] has run. It must
    not suspend for long and must not raise: a raise is a defect that replaces the outcome
    a waiting caller sees, keeping its backtrace. After the caller was cancelled or timed
    out, a [Drain] pool retains it and [Pool.shutdown] raises it; a [Detach_started] pool
    loses it. Use it to release a resource leased to the callback. ^nblk-2h3g ^nblock-l78q
*)

val try_run :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:(('a, exn) result -> unit) ->
  (unit -> 'a) ->
  'a try_run_outcome
(** Never waits for admission; returns [Not_run Saturated] if no slot is free. Raises
    [Invalid_argument] from worker startup on a finished or wrong-domain owner switch, as
    with [run]. ^nlintd-raises *)

val run_result :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:((('a, 'e) result, exn) result -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a, [ `Shutting_down | `Callback of 'e ]) result
(** Preserve callback errors as typed [`Callback e], distinct from pool failures. Raises
    [Invalid_argument] from worker startup on a finished or wrong-domain owner switch, as
    with [run]. ^nlintd-raises *)

type 'a lease_end =
  | Unclaimed
  | Settled of ('a, exn) result
      (** The terminal ownership notification, not a uniqueness or must-close proof.
          [Unclaimed] guarantees that the native callback cannot subsequently execute.
          [Settled] reports physical completion, including a native exception. *)

val run_leased_result :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  release:(('a, 'e) result lease_end -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a, [ `Shutting_down | `Requires_drain | `Callback of 'e ]) result
(** Retain a native lease independently of the waiting caller. The mandatory [release]
    runs exactly once: [Unclaimed] on admission rejection, cancellation before the actual
    worker claim, or worker startup failure; [Settled] only after physical completion.
    [Detach_started] is rejected before admission with [Error `Requires_drain] and
    [Unclaimed]. Callback errors remain [Error (`Callback e)]; native exceptions are
    defects with their original backtrace.

    Pools, callers and releases must use the same Eio domain. [Unclaimed] runs in the
    withdrawing caller or failed-start worker Eio context; [Settled] runs in the worker
    fiber on the pool owner's switch, never on the native thread. Neither release may
    await its own pool or close the owner switch. Releases must not suspend for long.
    [release] may raise: its exception is an accounted defect, not the legacy no-raise
    hook contract. A live caller receives it; when that caller is gone it is retained
    (exception and backtrace only, not a slot) and every Drain raises it after all slots
    are released. An [Unclaimed] release defect during cancellation is retained without
    replacing the original Eio cancellation. Use [Fun.protect] inside [release] when
    observer failure must not prevent the actual resource cleanup.

    Suspension: may suspend in admission, completion and caller-provided [release].
    Cancellation: propagates caller cancellation, withdrawing work before claim or
    requesting interruption via [on_cancel] at most once after claim (which must not
    raise), without releasing a claimed lease. Finalizers: no switch finalizer is
    registered; protected terminal delivery owns cleanup until [release] returns or
    raises. Locking: admission uses Eio synchronization; caller callbacks own their locks.
    Cancellation safety: unsafe because progress is lost to a cancelled caller while
    admitted native work may still commit effects. Startup on a finished or wrong-domain
    owner switch raises [Invalid_argument], after [Unclaimed]; owners must Drain before
    closing dependent resources.

    This seam does not enforce unique ownership, discharge a must-close obligation, or
    prevent raw [run]/[run_result], direct native calls, aliased handles, or early closes.
    The real production NemaOwner seam has not been migrated or authorized in this slice;
    no bypass restriction or production adoption is claimed and ticket 18 remains open.
    ^safe-zgfv ^safe-sw86 ^safe-bt9f ^safe-m6vf ^safe-fr73 ^safe-y047 ^safe-czoe
    ^safe-tlyw ^safe-m5sp ^safe-t37w ^safe-12o2 *)

val try_run_result :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:((('a, 'e) result, exn) result -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a try_run_outcome, [ `Callback of 'e ]) result
(** Raises [Invalid_argument] from worker startup on a finished or wrong-domain owner
    switch, as with [run]. ^nlintd-raises *)

val run_result_timeout :
  pool:Pool.t ->
  clock:_ Eio.Time.clock ->
  timeout:Ox.Duration.t ->
  on_timeout:'timeout ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:((('a, 'e) result, exn) result -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a, [ `Shutting_down | `Timed_out of 'timeout | `Callback of 'e ]) result
(** Timeout bounds the caller wait only. Started native work retains its slot; [on_cancel]
    runs once if timeout wins and work has not completed. Raises [Invalid_argument] from
    worker startup on a finished or wrong-domain owner switch, as with [run_result].
    ^nlintd-truth ^nlintd-raises *)

val try_run_result_timeout :
  pool:Pool.t ->
  clock:_ Eio.Time.clock ->
  timeout:Ox.Duration.t ->
  on_timeout:'timeout ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:((('a, 'e) result, exn) result -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a try_run_outcome, [ `Timed_out of 'timeout | `Callback of 'e ]) result
(** Raises [Invalid_argument] from worker startup on a finished or wrong-domain owner
    switch, as with [try_run_result]. ^nlintd-truth ^nlintd-raises *)
