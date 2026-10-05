(* ^safe-rxya ^safe-d197: defective reads are only compiled, never executed. *)
val array_upper : unit -> int
val array_empty : unit -> 'a
val array_negative : unit -> int
val string_upper : unit -> char
val string_empty : unit -> char
val string_negative : unit -> char
val bytes_upper : unit -> char

module A : sig
  val get : 'a array -> int -> 'a
end

val alias_upper : unit -> int
val value_alias : unit -> char
