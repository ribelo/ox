(* ^nonce-mjpe: canonical aliases remain ordinary casts; all three namespaces may be shadowed. *)
let direct (n : int) : string = Stdlib.Obj.magic n

module Alias = Stdlib.Obj

let aliased (n : int) : string = Alias.magic n

let opened (n : int) : string =
  let open Alias in
  magic n

let unreviewed_many (f : unit -> int) = Obj.magic_many f

module Obj = struct
  let magic n = n
  let magic_many n = n
end

let shadowed (n : int) = Obj.magic (Obj.magic_many n)

module Stdlib = struct
  module Obj = Obj
end

let shadowed_stdlib (n : int) = Stdlib.Obj.magic n
