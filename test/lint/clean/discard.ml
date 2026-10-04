(* ^nlint-hxar ^nlint-9ftb: all spike negative boundaries remain clean. *)
module Std = Stdlib
module Alias = Std
open Std

module Own = struct
  type ('a, 'e) result = Other of 'a
end

let homonym () = ignore (Own.Other 3 : (int, string) Own.result)

let clean () =
  ignore 3;
  let _ = true in
  ()

let handled () = match (Ok 4 : (int, string) result) with Ok _ -> () | Error _ -> ()

let shadow_function () =
  let ignore x = match x with Ok _ -> () | Error _ -> () in
  ignore (Ok 5)

let drop = Std.ignore
let value_alias () = drop (Ok 6 : (int, string) result)
let passed_discard () = (fun discard -> discard (Ok 7 : (int, string) result)) Std.ignore

let polymorphic x =
  let _ = x in
  ()

let later_instantiated () = polymorphic (Ok 1 : (int, string) result)

let intentional () =
  (* Best effort: retain the caller's original outcome. *)
  let _cleanup_result = (Ok () : (unit, string) result) in
  ()

module Stdlib = struct
  type ('a, 'e) result = Other of 'a

  let ignore _ = ()
end

let shadow_module () =
  let _ = (Stdlib.Other 10 : (int, string) Stdlib.result) in
  ()

let shadow_ignore () = Stdlib.ignore (Ok 11 : (int, string) Std.result)
