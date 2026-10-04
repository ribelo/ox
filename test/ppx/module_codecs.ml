(* ^nderive-sfta ^nderive-cd80 ^nderive-p4tq ^nderive-ufnu ^nderive-e5va *)
module type Public = sig
  type t = { count : int } [@@deriving yojson]
end

module First = struct
  type item = { city : string } [@@deriving yojson]

  type t = { item : item; nick : string option; count : int [@json.default 7] }
  [@@deriving yojson]

  module Reexport = struct
    type nonrec t = t [@@deriving yojson]
  end

  module Deep = struct
    type t = item list [@@deriving yojson]
    type tree = Leaf of int | Node of tree * tree [@@deriving yojson]

    type a = { b : b }
    and b = { value : int } [@@deriving yojson]
  end
end

module Second = struct
  type t = Idle | Pair of string * int [@@deriving yojson]
end

module Qualified = struct
  type t = { left : First.t; right : Second.t; deep : First.Deep.t } [@@deriving yojson]
end

module Only = struct
  type t = { secret : Manual_encoder.t; nick : string option } [@@deriving yojson_of]
end

module Constrained : sig
  type t = int [@@deriving yojson]
end = struct
  type t = int [@@deriving yojson]
end
