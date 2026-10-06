val elapsed : _ Eio.Time.Mono.t -> float
(** Suspension: never suspends in Eio itself; synchronous clock/provider work may block;
    behavior is delegated to Eio.Time.Mono.now, Mtime.span and Mtime.Span.to_float_ns.
    Cancellation: not a cancellation point in Eio itself; behavior is delegated to
    Eio.Time.Mono.now and Mtime. Cancellation safety: safe to re-run. Finalizers: none are
    registered. Locking: none are introduced. *)

val civil_delay : _ Eio.Time.clock -> float -> unit
(** Suspension: may suspend waiting for the supplied clock; behavior is delegated to
    Eio.Time.sleep. Cancellation: propagates Eio.Cancel.Cancelled at Eio.Time.sleep;
    behavior is delegated to Eio. Cancellation safety: safe to re-run. Finalizers: none
    are registered. Locking: none are introduced. *)

val metadata : _ Eio.Time.clock -> unit
(** Suspension: never suspends in Eio itself; synchronous clock/provider work may block;
    behavior is delegated to Eio.Time.now and Stdlib.Printf.sprintf. Cancellation: not a
    cancellation point in Eio itself; behavior is delegated to Eio.Time.now and
    Stdlib.Printf.sprintf. Cancellation safety: safe to re-run. Finalizers: none are
    registered. Locking: none are introduced. *)

val calendar_fraction : _ Eio.Time.clock -> int
(** Suspension: never suspends in Eio itself; synchronous clock/provider work may block;
    behavior is delegated to Eio.Time.now and Stdlib.floor. Cancellation: not a
    cancellation point in Eio itself; behavior is delegated to the clock provider.
    Cancellation safety: safe to re-run. Finalizers: none are registered. Locking: none
    are introduced. *)

val shadow : unit -> float
