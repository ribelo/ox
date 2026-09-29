(** State owned by one fiber, changed by serialized closures (Riot's [Agent], in the scope
    discipline of {!Actor}): the choice when a caller needs a shared counter, cache or
    small state holder rather than an application message protocol. There is no message
    type, no changes stream, no name and no link; {!Actor} remains the choice for a domain
    protocol.

    One owner fiber, a daemon of the creating switch, runs every closure — reads included
    — one at a time, in acceptance order, from a bounded mailbox. There is no snapshot
    that bypasses the queue. Closures run to completion protected from cancellation, so
    they must be short, must not block for long, and must never call back into their own
    agent (the call could not be answered: a deadlock). Immutability of the state and not
    leaking mutable aliases through replies are the author's discipline; serialization is
    not memory isolation or transactional rollback.

    {2 Cancellation and finalizers}

    The owner is cancelled when the switch's body and ordinary fibers have finished (or
    the switch fails); the switch waits for it before its [Eio.Switch.on_release] hooks.
    When the owner ends for any reason — the switch ended, or a closure or [init] raised —
    the mailbox closes, every pending reply and every fiber blocked on a full mailbox is
    released with [`Agent_stopped], and nothing waits forever. A caller that is itself
    cancelled sees the cancellation, never [`Agent_stopped]; a cancelled caller does not
    retract an operation the agent already accepted, and need not receive its
    acknowledgement.

    {2 Errors}

    An exception in [init] or in any closure (a {!cast} included) is a defect: it fails
    the owning switch unchanged, to be classified by {!Scope.run}. It can be restarted
    only if the caller deliberately puts that scope under a {!Supervisor}, which then
    creates a fresh agent rather than reviving a stopped handle. The [_result] operations
    carry a typed failure of the closure to the caller instead: the state is left as it
    was and the agent goes on. *)

type 'state t
(** A handle on the state; the type says nothing but the state's. *)

val create : ?capacity:int -> sw:Eio.Switch.t -> init:(unit -> 'state) -> unit -> 'state t
(** [create ~sw ~init ()] starts the owner on [sw]. ^nactor-75ef

    [init] runs once, in the owner fiber, before the first request, protected from
    cancellation. Requests made earlier wait in the mailbox.

    [capacity] bounds the mailbox (default 1024, at least 1); every operation queues on
    it.

    @raise Invalid_argument if [capacity < 1] or [sw] is finished or cancelled. *)

val get : 'state t -> fn:('state -> 'reply) -> ('reply, [> `Agent_stopped ]) result
(** [get agent ~fn] applies [fn] to the state in the owner and returns its reply. The
    state is not changed. *)

val update : 'state t -> fn:('state -> 'state) -> (unit, [> `Agent_stopped ]) result
(** [update agent ~fn] replaces the state with [fn state] and returns once the replacement
    is in place: a later request sees it. *)

val get_and_update :
  'state t -> fn:('state -> 'reply * 'state) -> ('reply, [> `Agent_stopped ]) result
(** [get_and_update agent ~fn] applies [fn], commits the new state and replies, atomically
    with respect to every other request. The pair is Riot's [(reply, state)], the reverse
    of {!Actor}'s handler. *)

val cast : 'state t -> fn:('state -> 'state) -> (unit, [> `Agent_stopped ]) result
(** [cast agent ~fn] enqueues [fn] like {!update} and returns without waiting for it to
    run: [Ok ()] means accepted, nothing more. It blocks, cancellably, while the mailbox
    is full; fire-and-forget is not unlimited buffering. An exception in [fn] fails the
    owning switch. *)

val update_result :
  'state t ->
  fn:('state -> ('state, ([> `Agent_stopped ] as 'e)) result) ->
  (unit, 'e) result
(** {!update} with a typed refusal: [Error e] from [fn] is returned to the caller and
    leaves the state unchanged. The error row is the caller's own and must admit
    [`Agent_stopped]. *)

val get_and_update_result :
  'state t ->
  fn:('state -> ('reply * 'state, ([> `Agent_stopped ] as 'e)) result) ->
  ('reply, 'e) result
(** {!get_and_update} with a typed refusal: [Error e] from [fn] is returned and leaves the
    state unchanged. *)
