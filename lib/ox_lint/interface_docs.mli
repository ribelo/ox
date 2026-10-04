open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio; resolving compiler
    interfaces may block the domain. Cancellation: not a cancellation point. Finalizers:
    none are registered. Locking: compiler caches retain their existing locking. *)

type value = {
  name : string;
  loc : Location.t;
  families : string list;
  behaviour : bool;
  cancel_safety : bool;
}
(** Typed interface inventory and documentation shape, never semantic verification.
    ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn *)

val iterator : caps:< Cap.fs_read ; .. > -> (value -> unit) -> Tast_iterator.iterator
(** Visit explicit [val] declarations in interfaces; an empty family list is out of scope.
*)

val behaviour :
  caps:< Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator

val cancel_safety :
  caps:< Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
