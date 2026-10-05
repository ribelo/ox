(* ^safe-01za: no unchecked primitive is exposed. *)
val identity : 'a -> 'a

module Unsafe : sig
  val identity : 'a -> 'a
end

module Alias = Unsafe

val reexport : 'a -> 'a
external opaque : 'a -> 'a = "%opaque"
val text : string
(* external misleading : 'a -> 'b = "%identity" *)
