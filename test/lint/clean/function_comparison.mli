(* ^safe-eeso ^safe-doj9: clean function-comparison fixture contract. *)
val physical : (int -> int) -> (int -> int) -> bool
val physical_not : (int -> int) -> (int -> int) -> bool
val ordinary : 'a -> 'a -> bool
val data : int -> int -> int
val dedicated : ((int -> int) -> 'a -> 'b) -> (int -> int) -> 'a -> 'b
val closure_list : (int -> int) -> (int -> int) -> bool

type action = { id : int; run : int -> int }

val same_action : action -> action -> bool
val user_equal : (int -> int) -> (int -> int) -> bool

module User : sig
  val compare : (int -> int) -> (int -> int) -> int
end

val user_compare : (int -> int) -> (int -> int) -> int
val aliased_user : (int -> int) -> (int -> int) -> int
val physical_alias : (int -> int) -> (int -> int) -> bool
val physical_partial : (int -> int) -> (int -> int) -> bool
val unapplied_structural : (int -> int) -> (int -> int) -> bool
val alias_data : int -> int -> bool
val shadow_after_alias : (int -> int) -> (int -> int) -> bool * bool

module Stdlib : sig
  val compare : (int -> int) -> (int -> int) -> int
  val ( = ) : (int -> int) -> (int -> int) -> bool
end

val impostor : (int -> int) -> (int -> int) -> int * bool
