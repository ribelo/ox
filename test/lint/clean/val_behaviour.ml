(* ^nlintd-truth: implementation-backed shape fixture. *)
let with_default _ = ()

module M = struct
  let inherited _ = ()
  let override _ = ()
end

let pure = string_of_int

type switch_alias = Eio.Switch.t
type recursive = Item of switch_alias | Next of recursive option
type box = { authority : < Ox_caps.Cap.env > }
type payload = [ `Authority of box ]

let variant _ = ()
let recursive _ = ()
let mutex _ = ()
let pool _ = ()

module Fake = struct
  type t = < env : int >

  let pure t = t#env
end

module Protected = struct
  let inside _ = ()
end
