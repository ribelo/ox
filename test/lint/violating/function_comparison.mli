(* ^safe-eeso ^safe-doj9: violating function-comparison fixture contract. *)
val equal : (int -> int) -> (int -> int) -> bool
val unequal : (int -> int) -> (int -> int) -> bool
val less : (int -> int) -> (int -> int) -> bool
val greater : (int -> int) -> (int -> int) -> bool
val less_equal : (int -> int) -> (int -> int) -> bool
val greater_equal : (int -> int) -> (int -> int) -> bool
val ordering : (int -> int) -> (int -> int) -> int

module Standard = Stdlib

val module_alias : (int -> int) -> (int -> int) -> bool
val opened : (int -> int) -> (int -> int) -> int
val eq : 'a -> 'a -> bool
val full_alias : (int -> int) -> (int -> int) -> bool
val eq_again : 'a -> 'a -> bool
val chained_alias : (int -> int) -> (int -> int) -> bool
val local_alias : (int -> int) -> (int -> int) -> int
val partial : (int -> int) -> (int -> int) -> bool
val nested_partial : (int -> int) -> (int -> int) -> bool
val partial_alias : (int -> int) -> (int -> int) -> bool

type callback = int -> int

val transparent : callback -> (int -> int) -> bool
val let_callee : (int -> int) -> (int -> int) -> int
