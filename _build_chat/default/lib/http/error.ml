type kind = Header_invalid of { reason : string }
type t = { method_ : string; uri : string; kind : kind }

let make ~method_ ~uri kind = { method_; uri; kind }
