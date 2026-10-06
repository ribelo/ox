(* ^nlintd-k036 *)
(** Cancellation and finalizers: Suspension: never suspends. Cancellation: not a cancellation point.
    Finalizers: none. Locking: none. *)

module Alias : sig
  val noop : Eio.Switch.t -> unit
end
module Included : sig
  val noop : Eio.Switch.t -> unit
end
val noop : Eio.Switch.t -> unit
