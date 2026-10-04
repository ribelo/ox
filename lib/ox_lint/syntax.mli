open Ocaml_common

type context
(** Lexically scoped module aliases and opens; ^nlint-rv8u. *)

val resolve : context -> Longident.t -> string list
(** Qualified aliases resolve; bare names return candidates from the open stack. *)

val module_origin : context -> Longident.t -> string option
(** Qualified module alias identity, excluding locally defined modules. *)

val value_origin : context -> Longident.t -> string option
(** Source binder identity: local values/modules shadow opens and Stdlib. External
    re-exports and opaque functors require the typed tier. ^ncapslint-nf4t *)

val walk : string -> (context -> Ast_iterator.iterator -> Ast_iterator.iterator) -> unit
(** Parse implementations/interfaces with docstrings enabled; parse errors propagate. *)
