(* ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn *)
(** Cancellation and finalizers: Suspension: never suspends; these are example
    declarations. Cancellation: not a cancellation point; no check is performed.
    Finalizers: none. Locking: none. *)

val with_default : Eio.Switch.t -> unit

module M : sig
  val inherited : 'a Eio.Flow.source -> unit

  val override : Eio.Switch.t -> unit
  (** Suspension: may suspend awaiting work. Cancellation: propagates. Finalizers:
      registered on the switch. Locking: held only during bookkeeping. *)
end

val pure : int -> string

type switch_alias = Eio.Switch.t
type recursive = Item of switch_alias | Next of recursive option
type box = { authority : < Ox_caps.Cap.env > }
type payload = [ `Authority of box ]

val variant : payload -> unit
val recursive : recursive -> unit
val mutex : Eio.Mutex.t -> unit
val pool : int Eio.Pool.t -> unit

module Fake : sig
  type t = < env : int >

  val pure : t -> int
end

(** Cancellation and finalizers: Suspension: may suspend in arbitrary callback code.
    Cancellation: protected throughout this example operation. Finalizers: none. Locking:
    none. *)
module Protected : sig
  val inside : Eio.Switch.t -> unit
end
