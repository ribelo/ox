(* ^safe-1kqm ^safe-l2jj: renaming a raw representation is not a domain. *)
type t = Yojson.Safe.t
let decode value = Ok value
