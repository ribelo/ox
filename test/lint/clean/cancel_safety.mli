(* ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn *)
(** Cancellation and finalizers: Suspension: never suspends; the shape-fixture stubs
    ignore their resource arguments. Cancellation: not a cancellation point; the stubs
    perform no check. Finalizers: none. Locking: none. Safety labels below are syntax
    examples for the represented operations, not runtime effects of these inert stubs.
    ^nlintd-a7oq *)

val safe : ('a, 'e) Ox.Channel.t -> unit
(** Cancellation safety: safe to re-run. *)

val data : 'a Eio.Flow.source -> unit
(** Cancellation safety: unsafe because data is lost: bytes may already be consumed. *)

val progress : Eio.Mutex.t -> unit
(** Cancellation safety: unsafe because progress is lost: queue position is discarded. *)

val synchronous : Eio.Switch.t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point. *)

val protected : Eio.Switch.t -> unit
(** Cancellation: protected throughout. *)

val pure : int -> string

(** Cancellation and finalizers: Cancellation safety: safe to re-run. *)
module Defaults : sig
  val inherited : 'a Eio.Time.Mono.t -> unit
end

val after : Eio.Switch.t -> unit
(** Cancellation safety: safe to re-run. *)
