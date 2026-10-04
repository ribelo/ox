(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)
[@@@warning "-32-34-37"]

let cast x = Obj.magic x

module O = Obj

let alias x = O.magic x

let opened x =
  let open Obj in
  magic x

let portable x = Obj.magic_portable x
