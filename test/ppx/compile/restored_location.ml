[@@@ocamlformat "disable"]
(* ^nderive-e5va: multiline attributes and inserted converters preserve later lines. *)
module M = struct
  type t = int
  [@@deriving
    yojson_of]
end

let after : int = "wrong"
