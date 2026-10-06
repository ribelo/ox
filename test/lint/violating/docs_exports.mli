(* ^nlintd-k036 *)
(** Cancellation and finalizers: Suspension: never suspends. Cancellation: not a cancellation point.
    Finalizers: none. Locking: none. *)

module Alias : sig
  val noop : Eio.Switch.t -> unit

  val unknown_raise : Eio.Switch.t -> unit
  (** Suspension: may suspend as delegated to Stdlib.Format.asprintf. Cancellation:
      depends on Stdlib.Format.asprintf. Finalizers: none. Locking: none.
      Cancellation safety: safe to re-run.
      @raise Failure if the delegated Helper fails. *)
end
module Included : sig
  val noop : Eio.Switch.t -> unit
end
val noop : Eio.Switch.t -> unit

val false_delegated_raise : Eio.Switch.t -> unit
(** Suspension: may suspend as delegated to Stdlib.Format.asprintf. Cancellation:
    propagates Eio.Cancel.Cancelled and may check as delegated to Stdlib.Format.asprintf.
    Finalizers: none. Locking: none.
    Cancellation safety: safe to re-run.
    @raise Failure if the delegated Concurrency_violating.Docs_dependency helper fails. *)

val unrelated_raise : Eio.Switch.t -> unit
(** Suspension: may suspend as delegated to Stdlib.Format.asprintf. Cancellation:
    propagates Eio.Cancel.Cancelled and may check as delegated to Stdlib.Format.asprintf.
    Finalizers: none. Locking: none.
    Cancellation safety: safe to re-run.
    @raise Failure if the delegated Concurrency_violating.Docs_dependency helper fails. *)
