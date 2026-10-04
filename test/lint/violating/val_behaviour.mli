[@@@ox_lint.fixture "ox-val-behaviour: deliberate negative fixture"]

val missing : Eio.Switch.t -> unit

module Clock = Eio.Time.Mono

type 'a deps = { caps : < Ox_caps.Cap.env >; clock : 'a Clock.t }

val nested : ('a deps -> unit) list -> unit

val flow : 'a Eio.Flow.source -> unit
(** Suspension: may suspend. Cancellation: propagates. Finalizers: none. *)

val incomplete : Eio.Switch.t -> unit
(** Suspension: sometimes. Cancellation: propagates. Finalizers: none. Locking: none. *)

module Local : sig
  module Switch : sig
    type t = int
  end

  val pure : Switch.t -> int
end

val dotted : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point. Finalizers: none.
    Locking: Eio.Switch.t *)

val duplicate : Eio.Switch.t -> unit
(** Suspension: never suspends. Suspension: never suspends. Cancellation: not a
    cancellation point. Finalizers: none. Locking: none. *)

val missing_period : Eio.Switch.t -> unit
(** Suspension: never suspends Cancellation: not a cancellation point. Finalizers: none.
    Locking: none. *)

val marker : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point. Finalizers: none.
    Locking: *)
