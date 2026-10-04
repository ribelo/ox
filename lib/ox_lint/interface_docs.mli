open Ocaml_common

type value = {
  name : string;
  loc : Location.t;
  families : string list;
  behaviour : bool;
  cancel_safety : bool;
}
(** Typed interface inventory and documentation shape, never semantic verification.
    ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn *)

val iterator : (value -> unit) -> Tast_iterator.iterator
(** Visit explicit [val] declarations in interfaces; an empty family list is out of scope.
*)

val behaviour : (Location.t -> unit) -> Tast_iterator.iterator
val cancel_safety : (Location.t -> unit) -> Tast_iterator.iterator
