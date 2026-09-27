module Syntax = struct
  let ( let* ) r f = match r with Ok x -> f x | Error e -> Error e
  let ( let+ ) r f = match r with Ok x -> Ok (f x) | Error e -> Error e
end
