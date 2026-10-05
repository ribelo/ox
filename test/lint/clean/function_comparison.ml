(* ^safe-doj9 ^safe-2led: accepted controls and domain-ID replacement. *)
let physical (f : int -> int) g = f == g
let physical_not (f : int -> int) g = f != g
let ordinary x y = x = y
let data (x : int) y = Stdlib.compare x y
let dedicated compare_function (f : int -> int) g = compare_function f g
let closure_list (f : int -> int) g = [ f ] = [ g ]

type action = { id : int; run : int -> int }

let same_action a b = Int.equal a.id b.id

let user_equal (f : int -> int) g =
  let ( = ) a b = a == b in
  f = g

module User = struct
  let compare (f : int -> int) g = if f == g then 0 else 1
end

let user_compare = User.compare

let aliased_user (f : int -> int) g =
  let compare = User.compare in
  compare f g

let physical_alias (f : int -> int) g =
  let equal = Stdlib.( == ) in
  equal f g

let physical_partial (f : int -> int) = Stdlib.( == ) f
let unapplied_structural (f : int -> int) = Stdlib.( = ) f

let alias_data x y =
  let equal = Stdlib.( = ) in
  equal (x : int) y

let shadow_after_alias (f : int -> int) g =
  let eq = Stdlib.( = ) in
  let before = eq 1 2 in
  let eq a b = a == b in
  (before, eq f g)

module Stdlib = struct
  let compare (f : int -> int) g = if f == g then 0 else 1
  let ( = ) (f : int -> int) g = f == g
end

let impostor (f : int -> int) g = (Stdlib.compare f g, Stdlib.( = ) f g)
