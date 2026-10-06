(* ^nlintd-b362 ^nlintd-2tmh *)
(** Cancellation and finalizers: Suspension: never suspends. Cancellation: not a cancellation point.
    Finalizers: none. Locking: none. *)

val forged_format : Eio.Switch.t -> string
val result_map : Eio.Switch.t -> unit
val result_map_error : Eio.Switch.t -> unit
val result_bind : Eio.Switch.t -> unit
val result_syntax : Eio.Switch.t -> unit
val partial_map : Eio.Switch.t -> unit
val option_map : Eio.Switch.t -> unit
val option_bind : Eio.Switch.t -> unit
val option_iter : Eio.Switch.t -> unit
val option_fold : Eio.Switch.t -> unit
val option_equal : Eio.Switch.t -> unit
val option_compare : Eio.Switch.t -> unit
val shadowed : Eio.Switch.t -> unit
val callback_yield : Eio.Switch.t -> unit
val functional_equal : Eio.Switch.t -> (unit -> unit) -> (unit -> unit) -> bool
val functional_list_equal : Eio.Switch.t -> (unit -> unit) list -> (unit -> unit) list -> bool
val option_get : Eio.Switch.t -> int option -> int
val returned_callback : Eio.Switch.t -> (unit -> unit) * int -> unit
