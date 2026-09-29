(** Direct-style bridge from Eio fibers to blocking native callbacks. Pools are owned by
    one Eio domain (worker-thread completion uses only thread-safe atomics/semaphores). A
    caller's cancellation never preempts a started callback. Do not release callback
    resources on caller cancellation: use [Pool.Drain] at the resource's owner scope
    and/or retain a separate lease until physical completion. No switch finalizers are
    registered by this package. *)

module Pool : sig
  type t
  type shutdown_policy = Drain | Detach_started
  type config = { max_threads : int; max_queued : int; shutdown_policy : shutdown_policy }

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
  (** Raises [Invalid_argument] for nonpositive [max_threads] or negative [max_queued].
      Only [max_threads] callbacks can physically run at once. [max_queued] bounds
      admitted waiting fibers; other [run] callers wait outside admission. The owner
      switch retains every worker fiber, including calls whose caller has timed out or
      cancelled. Shut down before releasing that switch. *)

  val shutdown_policy : t -> shutdown_policy
  val stats : t -> stats

  val shutdown : t -> unit
  (** Closes admission. [Drain] waits for all reserved slots to become free, including
      calls whose callers were cancelled or timed out. It must run outside a callback
      using this pool. [Detach_started] returns immediately, leaving started callbacks and
      their resources with the caller to manage. Neither policy interrupts a native
      callback. *)
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
    exceptions propagate with their backtrace as defects.

    [on_settled] (every [run] variant) is invoked exactly once, in the pool owner's Eio
    context (never the system thread), after the callback has physically finished, with
    its value or exception, also when the caller was cancelled or timed out long before.
    It is not invoked for a call abandoned before a worker claimed it (the callback never
    ran). It runs before a still-waiting caller sees the result and before the slot is
    released, so a [Drain] shutdown returns only after every [on_settled] has run. It must
    not suspend for long and must not raise: a raise replaces the outcome a waiting caller
    sees and is otherwise lost. Use it to release a resource leased to the callback.
    ^nblk-2h3g *)

val try_run :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:(('a, exn) result -> unit) ->
  (unit -> 'a) ->
  'a try_run_outcome
(** Never waits for admission; returns [Not_run Saturated] if no slot is free. *)

val run_result :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:((('a, 'e) result, exn) result -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a, [ `Shutting_down | `Callback of 'e ]) result
(** Preserve callback errors as typed [`Callback e], distinct from pool failures. *)

val try_run_result :
  pool:Pool.t ->
  ?name:string ->
  ?on_cancel:(unit -> unit) ->
  ?on_settled:((('a, 'e) result, exn) result -> unit) ->
  (unit -> ('a, 'e) result) ->
  ('a try_run_outcome, [ `Callback of 'e ]) result

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
    runs once if timeout wins and work has not completed. *)

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
