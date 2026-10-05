(* ^safe-d197 ^safe-xd2e ^safe-tlyw: clean fixture contract. *)
val array_first : unit -> int
val array_last : unit -> int
val string_last : unit -> char
val unicode_byte : unit -> char
val bytes_last : unit -> char
val checked_index : 'a array -> int -> ('a, [> `Index_out_of_bounds ]) result

module Array : sig
  val get : 'a -> 'b -> int
end

module String : sig
  val get : 'a -> 'b -> char
end

module Bytes : sig
  val of_string : 'a -> bytes
  val get : bytes -> int -> char
end

val shadow_array : unit -> int
val shadow_string : unit -> char
val shadow_origin : unit -> char
val shadow_value : unit -> int
val unknown_array : 'a array -> 'a
val unknown_string : string -> char
val unknown_bytes : bytes -> char
val unknown_index : int -> int
val unknown_origin : string -> char
val unknown_branch : bool -> int
