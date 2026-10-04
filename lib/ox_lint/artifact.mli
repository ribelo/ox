open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio; synchronous filesystem
    reads and Dune subprocess queries may block the domain. Cancellation: not a
    cancellation point. Finalizers: channels and subprocess handles are closed before
    returning; returned annotations are in-memory values. Locking: compiler caches and
    runtime I/O retain their existing locking. *)

type t = { path : string; info : Cmt_format.cmt_infos; builddir : string }

val read : caps:< Cap.fs_read ; .. > -> string -> t

type target = Library | Executable
type membership = Built of target | Not_built | Unknown

val membership : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> membership
(** Query Dune's declared modules, cached per project. [Not_built] requires a successful
    inventory; unavailable or failed inventories return [Unknown], never an exclusion. *)

val find : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> t
(** Match the recorded source identity in local and enclosing build object directories,
    including qualified subdirectories. Missing or unreadable evidence raises a named
    failure; coverage is never inferred from existing annotations. ^nlint-2nwm. *)

val setup : caps:< Cap.fs_read ; .. > -> t -> unit
(** Reset caches and initialize rebased visible and hidden include paths. *)

val source : t -> string
(** Resolve the annotation's source through its rebased build directory. *)

val check : caps:< Cap.fs_read ; .. > -> source:string -> t -> unit
(** Check source digest, original/preprocessed freshness and complete payload. *)
