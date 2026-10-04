open Ocaml_common

type t = {
  id : string;
  message : string;
  violating : string;
  clean : string;
  documentation : string;
  source :
    ((Location.t -> unit) ->
    Syntax.context ->
    Ast_iterator.iterator ->
    Ast_iterator.iterator)
    option;
  typed : ((Location.t -> unit) -> Tast_iterator.iterator) option;
}
(** Each rule owns its tier, replacement and evidence; ^nlint-emql. *)

val all : t list

val select : string list -> t list
(** Unknown ids raise [Invalid_argument]; empty selects all. *)

val self_check : root:string -> t list -> string list
(** Missing replacement, fixture or rule page produces a named failure. *)
