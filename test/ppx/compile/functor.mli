(* ^nderive-e5va: functor signatures cannot be partially generated. *)
module F : functor (X : sig end) -> sig
  type t = int [@@deriving yojson]
end
