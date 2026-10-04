open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio itself; compiler
    resolution may block the domain, effects are delegated to Stdlib, Ocaml_common and
    Ox_caps, and caller-callback effects depend on caller code. Cancellation: not a
    cancellation point itself; delegated Stdlib, Ocaml_common and Ox_caps operations and
    caller callbacks govern additional checks and are not checked here. Finalizers: none
    are registered by the analyser; callback-owned resources remain caller-owned. Locking:
    delegated compiler caches retain their existing locking. *)

type value = {
  name : string;
  loc : Location.t;
  families : string list;
  behaviour : bool;
  cancel_safety : bool;
  documentation : string list;
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

val truth :
  caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > ->
  source:string ->
  artifact:Artifact.t ->
  rules:string list ->
  emit:(string -> Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  unit
(** Check effective documentation against paired implementation and package-local typed
    reachability. Missing or opaque evidence is named through [undecided], never treated
    as proof. [emit] carries the rule ID, declaration location and concrete contradiction.
    The legacy iterators above remain sentence-shape checks. ^nlintd-truth ^nlintd-raises
    ^nlintd-cleanup *)
