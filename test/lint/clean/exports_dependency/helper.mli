(* ^nlintd-k036 *)
val noop : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point. Finalizers: none.
    Locking: none. *)
