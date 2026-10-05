(* ^safe-eeso: legal arrow instantiations of Stdlib comparisons. *)
let equal (f : int -> int) g = f = g
let unequal (f : int -> int) g = f <> g
let less (f : int -> int) g = f < g
let greater (f : int -> int) g = f > g
let less_equal (f : int -> int) g = f <= g
let greater_equal (f : int -> int) g = f >= g
let ordering (f : int -> int) g = Stdlib.compare f g

module Standard = Stdlib

let module_alias (f : int -> int) g = Standard.( = ) f g

let opened (f : int -> int) g =
  let open Stdlib in
  compare f g

let eq = Stdlib.( = )
let full_alias (f : int -> int) g = eq f g
let eq_again = eq
let chained_alias (f : int -> int) g = eq_again f g

let local_alias (f : int -> int) g =
  let cmp = Stdlib.compare in
  cmp f g

let partial (f : int -> int) g =
  let same_as_f = Stdlib.( = ) f in
  same_as_f g

let nested_partial (f : int -> int) g = (Stdlib.( <> ) f) g

let partial_alias (f : int -> int) g =
  let same_as_f = eq f in
  let next = same_as_f in
  next g

type callback = int -> int

let transparent (f : callback) g = f = g

let let_callee (f : int -> int) g =
  (let cmp = Stdlib.compare in
   cmp)
    f g
