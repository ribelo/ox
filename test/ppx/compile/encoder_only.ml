(* ^nderive-s2lt ^nderive-sfta: inferred interfaces must expose no decoder. *)
type t = int [@@deriving yojson_of]

module M = struct
  type t = int [@@deriving yojson_of]
end
