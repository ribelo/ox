(* ^nderive-9atb: abstract signature derivation exports only an encoder. *)
type t [@@deriving yojson_of]

val make : int -> t
