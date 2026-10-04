(* ^nlint-hxar: direct, wildcard, opened/module/type aliases and operator boundaries. *)
module Std = Stdlib
module Alias = Std
open Std

let direct () = ignore (Ok 1 : (int, string) result)

let wildcard () =
  let _ = (Error "x" : (int, string) result) in
  ()

type ('a, 'e) outcome = ('a, 'e) result

let type_alias () = Alias.ignore (Ok 2 : (int, string) outcome)
let with_operator () = Std.ignore @@ (Ok 8 : (int, string) result)
let pipeline () = (Ok 9 : (int, string) result) |> Std.ignore

let poly_rhs () =
  let _ = Ok 12 in
  ()

module Stdlib = struct
  type ('a, 'e) result = Other of 'a

  let ignore _ = ()
end

let still_canonical () = Alias.ignore (Ok 13 : (int, string) Std.result)
