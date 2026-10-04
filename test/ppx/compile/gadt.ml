(* ^nderive-07js ^nderive-e5va: GADTs remain unsupported. *)
module M = struct
  type t = C : t [@@deriving yojson]
end
