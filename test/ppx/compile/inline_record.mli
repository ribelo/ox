(* ^nderive-i3v2 ^nderive-e5va: signatures also reject inline records. *)
module M : sig
  type t = C of { x : int } [@@deriving yojson_of]
end
