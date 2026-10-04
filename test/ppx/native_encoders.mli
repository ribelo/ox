(* ^nderive-9atb ^nderive-p4tq: abstract/concrete and nested encoder signatures. *)
type t [@@deriving yojson_of]

val make : int -> t

type alias = Manual_encoder.t [@@deriving yojson_of]
type variant = Idle | One of int | Many of string * bool [@@deriving yojson_of]

type renamed = Plain [@json.name "plain"] | Payload of int [@json.name "payload"]
[@@deriving yojson_of]

type record = {
  secret : alias; [@json.key "secretKey"]
  omitted : string option;
  retained : int option; [@json.null]
  raw : Yojson.Safe.t;
  names : string list;
  pair : float * bool;
  grid : int array;
  initial : char;
  empty : unit;
  defaulted : int; [@json.default 7]
}
[@@deriving yojson_of]

type empty_object = unit [@@deriving yojson_of] [@@yojson.empty_record]
type tree = Leaf of int | Node of tree list [@@deriving yojson_of]

type a = A of b option
and b = { next : a list } [@@deriving yojson_of]

module Local : sig
  type leaf = Manual_encoder.t [@@deriving yojson_of]
  type t = { leaf : leaf } [@@deriving yojson_of]

  module Reexport : sig
    type nonrec t = t [@@deriving yojson_of]
  end
end
