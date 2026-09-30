(* lindec-4t98 lindec-ho00: twenty [@json.default] fields. The driver output of
   this file is the size regression. The old decoder copied the remaining continuation
   into both branches of every default, so this file's expansion was exponential. *)
type wide = {
  f00 : int; [@json.default 0]
  f01 : int; [@json.default 1]
  f02 : int; [@json.default 2]
  f03 : int; [@json.default 3]
  f04 : int; [@json.default 4]
  f05 : int; [@json.default 5]
  f06 : int; [@json.default 6]
  f07 : int; [@json.default 7]
  f08 : int; [@json.default 8]
  f09 : int; [@json.default 9]
  f10 : int; [@json.default 10]
  f11 : int; [@json.default 11]
  f12 : int; [@json.default 12]
  f13 : int; [@json.default 13]
  f14 : int; [@json.default 14]
  f15 : int; [@json.default 15]
  f16 : int; [@json.default 16]
  f17 : int; [@json.default 17]
  f18 : int; [@json.default 18]
  f19 : int; [@json.default 19]
}
[@@deriving yojson]
