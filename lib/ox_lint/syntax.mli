open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio; source and
    compiler-interface reads may block the domain. Cancellation: not a cancellation point.
    Finalizers: the source channel is closed on return or exception. Locking: compiler
    caches and channel operations retain their existing locking. *)

type context
(** Lexically scoped module aliases and opens; ^nlint-rv8u. *)

val resolve : context -> Longident.t -> string list
(** Qualified aliases resolve; bare names return candidates from the open stack. *)

val module_origin : context -> Longident.t -> string option
(** Qualified module alias identity, excluding locally defined modules. *)

val value_origin : caps:< Cap.fs_read ; .. > -> context -> Longident.t -> string option
(** Source binder identity: local values/modules shadow opens and Stdlib. External
    re-exports and opaque functors require the typed tier. ^ncapslint-nf4t *)

val walk :
  caps:< Cap.fs_read ; .. > ->
  string ->
  (context -> Ast_iterator.iterator -> Ast_iterator.iterator) ->
  unit
(** Parse implementations/interfaces with docstrings enabled; parse errors propagate.
    Suspension: may suspend if [make] or its iterator callbacks suspend. Cancellation:
    depends on those callbacks and propagates their exceptions. Cancellation safety:
    unsafe because progress is lost after earlier nodes have been visited; retries can
    repeat callback side effects. *)
