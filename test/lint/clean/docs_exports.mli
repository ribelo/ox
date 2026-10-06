(* ^nlintd-k036 *)
(** Cancellation and finalizers: Suspension: never suspends. Cancellation: not a
    cancellation point. Finalizers: none. Locking: none. *)

module Alias : sig
  val noop : Eio.Switch.t -> unit
end

module Included : sig
  val noop : Eio.Switch.t -> unit
end

val noop : Eio.Switch.t -> unit

val delegated_raise : Eio.Switch.t -> unit
(** Suspension: may suspend as delegated to Stdlib.Format.asprintf. Cancellation: depends
    on delegated to Stdlib.Format.asprintf. Finalizers: none. Locking: none. Cancellation
    safety: safe to re-run.
    @raise Failure if the delegated Concurrency_clean.Docs_dependency helper fails. *)
