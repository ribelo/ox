(* ^nlintd-k036 *)
val noop : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point.
    Finalizers: none. Locking: none. *)

val unknown_raise : Eio.Switch.t -> unit
(** Suspension: may suspend as delegated to Stdlib.Format.asprintf. Cancellation:
    depends on Stdlib.Format.asprintf. Finalizers: none. Locking: none.
    Cancellation safety: safe to re-run. *)
