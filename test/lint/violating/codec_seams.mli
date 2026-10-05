[@@@ox.domain]
type t = Yojson.Safe.t
val decode : Yojson.Safe.t -> (t, string) result
