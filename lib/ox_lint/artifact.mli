open Ocaml_common

type t = { path : string; info : Cmt_format.cmt_infos; builddir : string }

val read : string -> t

val find : string -> t
(** Locate an expected source's annotation; never infer coverage from existing artifacts.
    Missing or unreadable evidence raises a named failure; ^nlint-2nwm. *)

val setup : t -> unit
(** Reset caches and initialize rebased visible and hidden include paths. *)

val source : t -> string
(** Resolve the annotation's source through its rebased build directory. *)

val check : source:string -> t -> unit
(** Check source digest, original/preprocessed freshness and complete payload. *)
