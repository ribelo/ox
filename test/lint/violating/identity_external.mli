(* ^safe-9gfb: interface exposure is also a policy restriction. *)
external cast : 'a -> 'b = "%identity"
external same_type : 'a -> 'a = "%identity"

module Unsafe : sig
  external cast : 'a -> 'b = "%identity"
end

module Alias = Unsafe

val reexport : 'a -> 'b

include sig
  external included : 'a -> 'b = "%identity"
end

module type Cast = sig
  external declared : 'a -> 'b = "%identity"
end

module Make : functor () -> sig
  external cast : 'a -> 'b = "%identity"
end
