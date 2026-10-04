(* ^nderive-e5va: no derivation inside functors. *)
module F (X : sig end) = struct
  type t = int [@@deriving yojson_of]
end
