(* ^safe-01za: the compiler checks ordinary typed identity. *)
let identity value = value

module Unsafe = struct
  let identity value = value
end

module Alias = Unsafe

let reexport = Alias.identity

external opaque : 'a -> 'a = "%opaque"

let text = "%identity"
(* external misleading : 'a -> 'b = "%identity" *)
