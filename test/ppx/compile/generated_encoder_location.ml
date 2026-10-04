(* ^nderive-e5va: generated encoder errors cite the declaring module-local type. *)
module M = struct
  type secret = int
  type t = { value : secret } [@@deriving yojson_of]
end
