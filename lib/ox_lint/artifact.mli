open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio; synchronous filesystem
    reads and Dune subprocess queries may block the domain. Cancellation: not a
    cancellation point. Finalizers: channels and subprocess handles are closed before
    returning; returned annotations are in-memory values. Locking: compiler caches and
    runtime I/O retain their existing locking. *)

type t = { path : string; info : Cmt_format.cmt_infos; builddir : string }

val ignored :
  caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > ->
  directory:string ->
  string list ->
  string list
(** Return entries ignored by Git in [directory], without following their symlinks.
    Missing Git/repository information excludes nothing. Explicit source or annotation
    arguments override Git ignores, fixture skipping and data-only classification;
    directory discovery (including the data-dependency inventory) honors Git ignores, and
    missing named paths remain errors even if ignored. *)

val read : caps:< Cap.fs_read ; .. > -> string -> t

val fixture : caps:< Cap.fs_read ; .. > -> string -> string option
(** Parse a file-level fixture declaration, returning its named rule. Malformed or
    duplicate declarations fail; comments and nested attributes do not mark a file. *)

type target = Library | Executable
type membership = Built of target | Data_only | Not_built | Unknown

val membership : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> membership
(** Query Dune declarations, cached per project. [describe workspace] answers for
    libraries/executables; [describe rules --recursive @check] supplies compilation
    sources omitted by workspace (notably [test]/[tests] on Dune 3.22). Dune resolves
    module sets and includes; existing annotations are never membership evidence. Absent
    compilation, a declared literal file, [source_tree] or [glob_files] dependency yields
    [Data_only]; [Not_built] means neither compiled nor consumed as data. Compilation
    always wins. Alias data declarations are read from Dune stanzas because
    [describe rules] omits alias actions. A failed query or unrecognised format returns
    [Unknown], never an exclusion. *)

val find : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> t
(** Match the recorded source identity in local and enclosing build object directories,
    including qualified subdirectories. Missing or unreadable evidence raises a named
    failure; coverage is never inferred from existing annotations. ^nlint-2nwm. *)

val setup : caps:< Cap.fs_read ; .. > -> t -> unit
(** Reset caches and initialize rebased visible and hidden include paths, including Dune
    private CMIs in installed [.private] and build-tree [byte] directories. Recorded paths
    take precedence; every imported CMI fingerprint must still match. *)

val source : t -> string
(** Resolve the annotation's source through its rebased build directory. *)

val check : caps:< Cap.fs_read ; .. > -> source:string -> t -> unit
(** Check source digest, original/preprocessed freshness and complete payload. *)
