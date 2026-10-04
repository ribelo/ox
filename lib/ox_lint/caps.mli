open Ocaml_common
(** Compiler-resolved capability rules. ^ncapslint-nf4t ^ncapslint-8jcy *)

type operation = { name : string; calls : string list list }

val operations : operation list

val source :
  string ->
  (Location.t -> unit) ->
  Syntax.context ->
  Ast_iterator.iterator ->
  Ast_iterator.iterator

val raw : string -> (Location.t -> unit) -> Tast_iterator.iterator
val signature : (Location.t -> unit) -> Tast_iterator.iterator
