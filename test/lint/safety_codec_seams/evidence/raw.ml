type json = Yojson.Safe.t
type 'a box = { payload : 'a option }
module type Direct = sig val raw : Yojson.Safe.t end
module type Aliased = sig val renamed : json list end
module type Applied = sig val wrapped : json box end
module type Callback = sig val use : callback:(json -> unit) -> unit end
module type Objects = sig val erased : Obj.t option end
module type Rows = sig val row : [ `Raw of json * int ] end
module type Object_row = sig val row : < raw : json > end
module type Nested = sig module Inner : Direct end
module type Included = sig include Direct end
module type Renamed = sig val decode : json -> (json, string) result end
module type Rec = sig type t = Leaf of json | Node of t list end
module type Signature_alias = Direct
