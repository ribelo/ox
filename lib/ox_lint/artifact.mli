open Ocaml_common

type t = { path : string; info : Cmt_format.cmt_infos; builddir : string }

val read : string -> t

type target = Library | Executable
type membership = Built of target | Not_built | Unknown

val membership : string -> membership
(** Query Dune's declared modules, cached per project. [Not_built] requires a successful
    inventory; unavailable or failed inventories return [Unknown], never an exclusion. *)

val find : string -> t
(** Match the recorded source identity in local and enclosing build object directories,
    including qualified subdirectories. Missing or unreadable evidence raises a named
    failure; coverage is never inferred from existing annotations. ^nlint-2nwm. *)

val setup : t -> unit
(** Reset caches and initialize rebased visible and hidden include paths. *)

val source : t -> string
(** Resolve the annotation's source through its rebased build directory. *)

val check : source:string -> t -> unit
(** Check source digest, original/preprocessed freshness and complete payload. *)
