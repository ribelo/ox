(* ^nlintc-kdcl: obj_magic clean evidence. *)
[@@@warning "-32-34-37"]

let typed x = x

module Obj = struct
  let magic x = x
  let magic_portable x = x
end

let shadowed x = Obj.magic_portable (Obj.magic x)
