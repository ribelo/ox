(** A bounded channel that can be closed, in Ox's shape: [send]/[receive] block on
    capacity, [done_] ends a stream normally and [error] ends it with a typed failure.
    {!Eio.Stream} has no close, and a closed channel is exactly what {!Select} must report
    as an outcome rather than an exception, so this small type exists beside it.

    A channel is a plain value: it owns no fiber, no switch and no finalizer. Blocking
    operations suspend the calling fiber on an {!Eio.Condition} and are promptly
    cancellable; cancellation propagates as Eio's cancellation and never changes the
    channel. Like every Eio condition the channel belongs to one domain: create and use it
    from the fibers of a single domain. *)

(** Cancellation and finalizers: Suspension: never suspends for creation, polling or
    closing. Cancellation: not a cancellation point for creation, polling or closing.
    Finalizers: none are registered; the channel owns no fiber or switch. Locking: no
    mutex is held; queue updates contain no suspension. ^nlintd-a7oq *)

type ('a, 'e) t
(** Elements of type ['a]; ['e] is the payload of {!error}. *)

type 'e closed = [ `Done | `Error of 'e ]
(** Why a channel refuses an operation: [`Done] after {!done_} (a receiver sees it once
    the buffer is drained), [`Error e] after {!error}. *)

val create : ?capacity:int -> unit -> ('a, 'e) t
(** [create ?capacity ()] is an open channel buffering at most [capacity] elements
    (default 16, Ox's default buffer). Rendezvous (capacity 0) is not offered: a {!Select}
    over rendezvous channels cannot be built on non-blocking probes.
    @raise Invalid_argument if [capacity < 1]. *)

val send : ('a, 'e) t -> 'a -> (unit, 'e closed) result
(** [send t v] appends [v], suspending while the buffer is full. [Error] when the channel
    is closed, at once or while waiting: the element is then not sent. Suspension: may
    suspend waiting for a queue change. Cancellation: propagates from the condition wait;
    a successful queue operation does not suspend. Cancellation safety: safe to re-run;
    cancellation while waiting has not enqueued or removed an item. ^nlintd-a7oq *)

val receive : ('a, 'e) t -> ('a, 'e closed) result
(** [receive t] takes the oldest element, suspending while the buffer is empty. After
    {!done_} the remaining elements are still delivered, then [Error `Done] forever; after
    {!error} the buffer is dropped and every call is [Error (`Error e)]. Suspension: may
    suspend waiting for a queue change. Cancellation: propagates from the condition wait;
    a successful queue operation does not suspend. Cancellation safety: safe to re-run;
    cancellation while waiting has not enqueued or removed an item. ^nlintd-a7oq *)

val try_send : ('a, 'e) t -> 'a -> (unit, [ `Full | 'e closed ]) result
(** {!send} that never suspends: [Error `Full] when there is no room. *)

val try_receive : ('a, 'e) t -> ('a, [ `Empty | 'e closed ]) result
(** {!receive} that never suspends: [Error `Empty] when there is nothing to take. *)

val done_ : ('a, 'e) t -> unit
(** Close the channel normally: senders are refused from now on and receivers drain the
    buffer, then see [`Done]. Has no effect on a channel that already failed; idempotent.
    Wakes every fiber blocked on the channel. *)

val error : ('a, 'e) t -> 'e -> unit
(** Close the channel with failure [e]: the buffer is dropped, and senders and receivers
    alike see [`Error e]. The first error wins; later calls do nothing. Wakes every fiber
    blocked on the channel. *)

val wait_changed : ('a, 'e) t -> unit
(** Suspend until the channel's state changes (an element sent or taken, or it closed).
    The building block of {!Select}: probe with {!try_send}/{!try_receive}, and call this
    only when no probe succeeded, with no suspension in between. Cancellable. Suspension:
    may suspend until the condition is broadcast. Cancellation: propagates from
    Eio.Condition.await_no_mutex. Cancellation safety: safe to re-run; this wait changes
    neither the queue nor the channel state. ^nlintd-a7oq *)
