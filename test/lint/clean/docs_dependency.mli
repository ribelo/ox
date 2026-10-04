(* ^nlintd-truth *)

val noop : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point. Finalizers: none.
    Locking: none. *)

val check : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: propagates. Finalizers: none. Locking: none.
    Cancellation safety: safe to re-run. Raises Eio.Cancel.Cancelled for a failed switch
    and Invalid_argument for a finished switch. *)
