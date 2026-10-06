val ready : unit -> unit

val finite : _ Eio.Time.clock -> unit
(** Suspension: may suspend in Eio.Time.sleep for the literal finite delay. Cancellation:
    protected throughout; pending cancellation is deferred to a later cancellation point.
    Finalizers: none. Locking: none. Cancellation safety: safe to re-run. ^safe-vj9b *)

val local : unit -> unit
val dormant : unit -> unit -> 'a

module Shadow : sig
  val protect : (unit -> 'a) -> 'a
  val await_cancel : unit -> unit
end

val shadow : unit -> unit

val unmasked : Eio.Mutex.t -> unit
(** Suspension: may suspend in mutex acquisition and Eio.Fiber.yield. Cancellation:
    propagates Eio.Cancel.Cancelled at acquisition and callback yield. Finalizers:
    releases the mutex after normal or exceptional callback completion. Locking: holds the
    supplied mutex during the callback. Cancellation safety: safe to re-run. ^safe-ctc4 *)

val partial : unit -> unit -> 'a

val partial_server : [> `Generic | `Unix ] Eio.Net.listening_socket -> unit
(** Suspension: never suspends; discards an unsaturated Eio.Net.run_server without
    executing it; a later saturated call delegates to Eio.Net.run_server and its
    callbacks. Cancellation: not a cancellation point; the unsaturated server delegates to
    Eio.Net.run_server and its callbacks only if later executed. Finalizers: none; the
    socket remains caller-owned. Locking: none. Cancellation safety: safe to re-run.
    ^safe-tcqo *)

val opaque_cleanup : (unit -> 'a) -> 'a
