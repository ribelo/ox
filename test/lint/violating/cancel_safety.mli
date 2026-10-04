(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

val receive : ('a, 'e) Ox.Channel.t -> unit
(** Suspension: may suspend. Cancellation: propagates. Finalizers: none. Locking: none. *)

val unknown : Eio.Switch.t -> unit

val vague : 'a Eio.Flow.source -> unit
(** Cancellation safety: safe. *)

module Good : sig
  (** Cancellation and finalizers: Cancellation safety: safe to re-run. *)

  val default : Eio.Switch.t -> unit

  val override : Eio.Switch.t -> unit
  (** Suspension: may suspend. Cancellation: propagates. *)
end

val sibling : Eio.Switch.t -> unit

val empty : Eio.Switch.t -> unit
(** Cancellation safety: unsafe because data is lost *)
