module type Empty = sig end
let package = (module struct end : Empty)
type extensible = ..
class type callback = object method run : unit end
module F (X : sig type t end) = struct let produce : X.t = failwith "abstract fixture" end
