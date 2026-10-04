(* ^nderive-s2lt ^nderive-u3ux ^nderive-9atb ^nderive-07js ^nderive-i3v2 *)
type t = int [@@deriving yojson_of]

let make value = value

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

module Local = struct
  type leaf = Manual_encoder.t [@@deriving yojson_of]
  type t = { leaf : leaf } [@@deriving yojson_of]

  module Reexport = struct
    type nonrec t = t [@@deriving yojson_of]
  end
end
