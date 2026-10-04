open Ocaml_common

type context
(** Lexically scoped module aliases and opens; ^nlint-rv8u. *)

val resolve : context -> Longident.t -> string list
(** Qualified aliases resolve; bare names return candidates from the open stack. *)

val walk : string -> (context -> Ast_iterator.iterator -> Ast_iterator.iterator) -> unit
(** Parse implementations/interfaces with docstrings enabled; parse errors propagate. *)
