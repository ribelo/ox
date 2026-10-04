(* ^nderive-e5va: generated decoder errors cite the same declaration, not helper lines. *)
module M = struct
  type secret = int

  let yojson_of_secret value : Yojson.Safe.t = `Int value

  type t = { value : secret } [@@deriving yojson]
end
