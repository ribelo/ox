(* ^nderive-p4tq ^nderive-ufnu: ordinary nested signatures and module types. *)
module type Public = sig
  type t = { count : int } [@@deriving yojson]
end

module First : sig
  type item = { city : string } [@@deriving yojson]

  type t = { item : item; nick : string option; count : int [@json.default 7] }
  [@@deriving yojson]

  module Reexport : sig
    type nonrec t = t [@@deriving yojson]
  end

  module Deep : sig
    type t = item list [@@deriving yojson]
    type tree = Leaf of int | Node of tree * tree [@@deriving yojson]

    type a = { b : b }
    and b = { value : int } [@@deriving yojson]
  end
end

module Second : sig
  type t = Idle | Pair of string * int [@@deriving yojson]
end

module Qualified : sig
  type t = { left : First.t; right : Second.t; deep : First.Deep.t } [@@deriving yojson]
end

module Only : sig
  type t = { secret : Manual_encoder.t; nick : string option } [@@deriving yojson_of]
end

module Constrained : sig
  type t = int [@@deriving yojson]
end
