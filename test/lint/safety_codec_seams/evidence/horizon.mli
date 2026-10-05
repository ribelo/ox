[@@@ox.domain]
module type Empty = sig end
val package : (module Empty)
type extensible = ..
class type callback = object method run : unit end
module F : functor (X : sig type t end) -> sig val produce : X.t end
