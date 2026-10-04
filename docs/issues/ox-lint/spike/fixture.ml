(* Boundary fixtures, compiled only, never executed. *)
module Std = Stdlib
module Alias = Std
open Std
let direct () = ignore (Ok 1 : (int, string) result)
let wildcard () = let _ = (Error "x" : (int, string) result) in ()
type ('a, 'e) outcome = ('a, 'e) result
let type_alias () = Alias.ignore (Ok 2 : (int, string) outcome)
module Own = struct type ('a, 'e) result = Other of 'a end
let homonym () = ignore (Own.Other 3 : (int, string) Own.result)
let clean () = ignore 3; let _ = true in ()
let handled () = match (Ok 4 : (int, string) result) with Ok _ -> () | Error _ -> ()
let shadow_function () = let ignore x = match x with Ok _ -> () | Error _ -> () in ignore (Ok 5)
module E = Eio
module F = E.Fiber
open F
let opened_fork ~sw () = fork ~sw (fun () -> ())
let aliased_fork ~sw () = F.fork ~sw (fun () -> ())
let local_fork () = let fork _ = () in fork ()
module C = E.Cancel
open C
let opened_cancel ex = match ex with Cancelled _ -> true | _ -> false
exception Stopped = C.Cancelled
let rebound_cancel ex = match ex with Stopped _ -> true | _ -> false
(* Explicitly out of this prototype's scope: higher-order/value aliases. *)
let drop = Std.ignore
let value_alias () = drop (Ok 6 : (int, string) result)
let passed_discard () = (fun discard -> discard (Ok 7 : (int, string) result)) Std.ignore
let with_operator () = Std.ignore @@ (Ok 8 : (int, string) result)
let pipeline () = (Ok 9 : (int, string) result) |> Std.ignore
module Stdlib = struct
  type ('a, 'e) result = Other of 'a
  let ignore _ = ()
end
let shadow_module () = let _ = (Stdlib.Other 10 : (int, string) Stdlib.result) in ()
let shadow_ignore () = Stdlib.ignore (Ok 11 : (int, string) Std.result)
