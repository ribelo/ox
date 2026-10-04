(* ^nderive-e5va: attributes inside expression subtrees are not ignored. *)
module type S = sig
  type t
end

let value =
  (module struct
    type t = int [@@deriving yojson_of]
  end : S)
