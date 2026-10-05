type unrelated = Yojson.Safe.t
module Domain : sig
  [@@@ox.domain]
  type t = { payload : Yojson.Safe.t }
end
