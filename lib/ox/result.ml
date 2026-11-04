module Syntax = struct
  let ( let* ) r f = match r with Ok x -> f x | Error e -> Error e
  let ( let+ ) r f = match r with Ok x -> Ok (f x) | Error e -> Error e
end

(* ^nlet-q79e: the continuation is called directly, so a local once yielding
   closure needs no conversion. *)
let bind r (f @ local once yielding) = match r with Ok x -> f x | Error e -> Error e
let map r (f @ local once yielding) = match r with Ok x -> Ok (f x) | Error e -> Error e
let both a b = match (a, b) with Ok x, Ok y -> Ok (x, y) | (Error e, _ | _, Error e) -> Error e
