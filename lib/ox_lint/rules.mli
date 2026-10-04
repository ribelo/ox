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

val all : caps:< Ox_caps.Cap.fs_read ; .. > -> t list

val allowances : (string * string * string) list
(** The shipped per-rule allow-list is empty; retained for future explicit policy;
    ^nlintc-j03j ^nlintc-7be1. *)

val applies : root:string -> source:string -> t -> bool
(** Raw concurrency is dormant on every path. Other rules apply to all implementations or,
    for interface rules, all interfaces; direct decider tests do not apply this policy. *)

val select : caps:< Ox_caps.Cap.fs_read ; .. > -> string list -> t list
(** Unknown ids raise [Invalid_argument]; empty selects all. *)

val self_check : caps:< Ox_caps.Cap.fs_read ; .. > -> root:string -> t list -> string list
(** Missing replacement, fixture or rule page produces a named failure. *)
