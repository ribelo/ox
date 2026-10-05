[@@@ox.domain]
type copy = { raw : Yojson.Safe.t }
val sanitize : Yojson.Safe.t -> copy
