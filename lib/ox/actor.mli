(** A typed mailbox over one state, folded by one fiber, supervised by the switch that
    created it (Ox's [Actor] scope discipline with GenServer's explicit-state handler).

    The fiber that owns the state runs [handle] on one message at a time, in arrival
    order, so the state needs no lock. The state is the author's value; immutability is a
    discipline, not something enforced. There is no schema, RPC binding, persistence or
    cluster: the protocol is the variant type of ['msg].

    {2 Cancellation and finalizers}

    The actor's fiber is a daemon of the creating switch. It is cancelled when that
    switch's body and its ordinary fibers have finished (or when the switch fails), and
    the switch waits for it before running its [Eio.Switch.on_release] hooks. A handler
    invocation is protected from that cancellation ([Eio.Cancel.protect]), so it finishes;
    a handler must therefore not suspend for an unbounded time and must not {!ask} its own
    actor (the reply could never be produced). Cancellation is checked between messages,
    so a stopping actor does not keep working through a full mailbox.

    An actor stops exactly once, in this order: the mailbox is closed, every message still
    in it (and the one being handled, if the handler raised) has its {!ask} answered
    [`Actor_stopped], every {!Changes} subscription ends, and then [on_stop] runs. The
    same happens whether the switch ended, was cancelled, or a handler raised.

    {2 Errors}

    A handler returning [Error e] is a typed failure: the asker gets [Error e] and the
    state is left as it was; the actor goes on. A handler raising an exception is a defect
    (ADR-0009): the actor stops and the exception fails its switch unchanged, to be
    classified by {!Scope.run}; no [result] carries it. The error type ['e] is one
    polymorphic-variant row shared by the handler and {!ask}: it must admit
    [`Actor_stopped] and [`Timeout], which the actor adds and the handler never needs to
    return. *)

(** Cancellation and finalizers: Suspension: never suspends for state reads, polling and
    subscription bookkeeping. Cancellation: not a cancellation point for state reads,
    polling and subscription bookkeeping. Finalizers: handle operations register no switch
    hook; subscriptions must be closed by their owner. Locking: no lock is acquired by
    this wrapper around caller code; Eio stream and promise locking is delegated.
    ^nlintd-a7oq *)

type ('state, 'msg, 'reply, 'e) t
(** An actor folding messages of type ['msg] over a ['state], answering with ['reply] or
    the handler's typed failure ['e]. (^nactor-agcr: the spec names three parameters; the
    state is a fourth because {!state} and {!changes} return it.) *)

val create :
  ?capacity:int ->
  ?on_stop:('state -> unit) ->
  sw:Eio.Switch.t ->
  init:'state ->
  handle:
    ('state -> 'msg -> ('state * 'reply, ([> `Actor_stopped | `Timeout ] as 'e)) result) ->
  unit ->
  ('state, 'msg, 'reply, 'e) t
(** [create ~sw ~init ~handle ()] starts the actor's fiber on [sw]. ^nactor-agcr

    [handle state msg] is the whole behaviour: the next state and the reply, or a typed
    failure that leaves the state unchanged (^nactor-7qi7). It runs in the actor's fiber,
    protected from cancellation, one message at a time (^nactor-mb6v). An exception it
    raises ends the actor and fails [sw] with it (^nactor-pxfz).

    [capacity] bounds the mailbox (default 1024, at least 1): {!tell} blocks when it is
    full and {!try_tell} answers [false] (^nactor-512k).

    [on_stop state] runs once when the actor stops, with the final state — the state after
    the last successful handler — protected from cancellation so it may persist or report
    (^nactor-oxao). It runs after the mailbox is closed and the pending asks answered, and
    before the releases registered on [sw]. If it raises, that exception fails [sw] too
    (together with a handler's, when both).

    The actor lives exactly as long as [sw] (^nactor-e0l5).

    Suspension: may suspend while the daemon starts. Cancellation: propagates
    Eio.Cancel.Cancelled from the initial switch check for a cancelled context; a finished
    switch raises Invalid_argument instead. Finalizers: the owning switch cancels and
    joins the daemon before its release hooks; no on_release hook is installed here.
    Locking: no lock is held by this wrapper around handler callbacks. ^nlintd-a7oq

    @raise Invalid_argument if [capacity < 1] or [sw] is finished. *)

val ask :
  ?timeout:'c Eio.Time.clock * Duration.t ->
  ('state, 'msg, 'reply, ([> `Actor_stopped | `Timeout ] as 'e)) t ->
  'msg ->
  ('reply, 'e) result
(** [ask actor msg] enqueues [msg] and waits for its reply. ^nactor-jhl2

    The result is the handler's [Ok reply] or its [Error e] (^nactor-7qi7), or
    [Error `Actor_stopped] when the actor has stopped or stops before answering
    (^nactor-pxfz ^nactor-e0l5). It blocks while the mailbox is full, like {!tell}.

    [timeout] is a clock and a limit for the wait (^nactor-tc19): on expiry the result is
    [Error `Timeout] and the actor is undisturbed. The message stays queued and is still
    handled, its reply dropped — a timeout says nothing about whether the message took
    effect. A caller that is cancelled while waiting leaves its message queued the same
    way, and the cancellation propagates. Suspension: may suspend while the mailbox is
    full and while awaiting a reply. Cancellation: propagates from the channel or promise
    wait, including the timeout wrapper's caller cancellation. Cancellation safety: unsafe
    because data is lost; an accepted message's eventual reply is inaccessible to a
    cancelled caller and the message may still be handled. ^nlintd-a7oq *)

val tell : ('state, 'msg, _, _) t -> 'msg -> unit
(** [tell actor msg] enqueues [msg] and returns without waiting for it to be handled.
    ^nactor-jhl2 It blocks while the mailbox is full (^nactor-512k), cancellably. A
    handler's [Error] for a told message has nobody to report to and is dropped. Telling
    an actor that has stopped drops the message. Suspension: may suspend while the mailbox
    is full. Cancellation: propagates from the channel wait; admission itself does not
    suspend. Cancellation safety: safe to re-run; interruption while waiting has not
    admitted the message. ^nlintd-a7oq *)

val try_tell : ('state, 'msg, _, _) t -> 'msg -> bool
(** Like {!tell} but never blocks: [false] when the mailbox is full or the actor has
    stopped, [true] when the message was enqueued. ^nactor-512k *)

val state : ('state, _, _, _) t -> 'state
(** The state after the last successful handler, read without sending a message, so a
    cheap read never queues behind writes (^nactor-l87k). After the actor stops it is the
    final state. It never shows a state a handler is still computing. *)

(** Observers of the state stream (^nactor-6z3i). *)
module Changes : sig
  type 'state t
  (** A subscription: a bounded buffer of the states the actor produced since it was
      created. Each subscription has its own buffer, so several observers do not take from
      one another. Abandoning one without {!close} keeps at most [capacity] states alive
      until the actor stops. *)

  val next : 'state t -> 'state option
  (** The oldest buffered state, waiting for one if there is none; [None] once the actor
      has stopped (or the subscription was closed) and the buffer is drained. Cancellable
      while waiting. Suspension: may suspend until an update or end marker arrives.
      Cancellation: propagates from Eio.Stream.take. Cancellation safety: safe to re-run;
      a cancelled stream waiter has not taken an update. Locking: Eio.Stream.take releases
      its internal mutex before waiting. ^nlintd-a7oq *)

  val dropped : 'state t -> int
  (** How many states were discarded because the observer fell more than [capacity]
      behind. Overflow drops the oldest state, so the newest are always kept and the count
      says how many were missed. *)

  val close : 'state t -> unit
  (** Stops receiving states and discards the buffered ones: a waiting {!next} and every
      later one answer [None]. Idempotent. *)
end

val changes : ?capacity:int -> ('state, _, _, _) t -> 'state Changes.t
(** [changes actor] subscribes to the state after each successful handler, in order
    (^nactor-6z3i). Only states produced after the call are delivered: read {!state} first
    to start from the current one. [capacity] (default 64, at least 1) bounds the buffer.
    Subscribing to a stopped actor gives a subscription that has already ended.

    @raise Invalid_argument if [capacity < 1]. *)
