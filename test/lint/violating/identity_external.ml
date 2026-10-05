(* ^safe-9gfb: compiler-accepted unchecked representation claim. *)
external cast : 'a -> 'b = "%identity"
external same_type : 'a -> 'a = "%identity"

module Unsafe = struct
  external cast : 'a -> 'b = "%identity"
end

module Alias = Unsafe

let reexport = Alias.cast

include struct
  external included : 'a -> 'b = "%identity"
end

module type Cast = sig
  external declared : 'a -> 'b = "%identity"
end

module Make () = struct
  external cast : 'a -> 'b = "%identity"
end
