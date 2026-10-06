(* ^nlintd-7x5n ^nlintd-b362 ^nlintd-2tmh *)
(** Cancellation and finalizers: Suspension: never suspends. Cancellation: not a
    cancellation point. Finalizers: none. Locking: none. *)

val scalar_format : Eio.Switch.t -> int -> int -> int -> int64 -> string
val function_list_empty : Eio.Switch.t -> (unit -> unit) list -> bool
val polymorphic_list_empty : Eio.Switch.t -> 'a list -> bool

val totals :
  Eio.Switch.t -> int * int -> int option -> (int, string) result -> int list -> unit

val aliases : Eio.Switch.t -> (int, string) result -> unit
val stored_function : Eio.Switch.t -> (unit -> unit) -> unit
val callbacks : Eio.Switch.t -> (int, string) result -> int option -> unit
val unused_partial : Eio.Switch.t -> unit
val caught_callback : Eio.Switch.t -> (int, string) result -> unit
