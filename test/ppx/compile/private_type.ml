(* ^nderive-07js ^nderive-e5va: private types still fail clearly. *)
module M = struct
  type t = private int [@@deriving yojson_of]
end
