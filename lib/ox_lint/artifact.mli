open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio itself; synchronous
    filesystem/compiler work may block the domain; operations delegate to Stdlib, Unix,
    Ox_caps, Cmt_format, Cmi_format, Compilation_unit, Envaux, Import_info and Load_path
    and their higher-order callbacks; capability object method dispatch depends on the
    supplied provider; running returned visitors depends on caller code. Cancellation: not
    a cancellation point in Eio itself; operations delegate to Stdlib, Unix, Ox_caps,
    Cmt_format, Cmi_format, Compilation_unit, Envaux, Import_info and Load_path and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider; running returned visitors depends on caller code; Failure reports missing
    metadata, invalid build-directory rebasing, failed rebuilds or stale/missing
    annotation evidence. Finalizers: channels and subprocess handles are closed before
    returning; returned annotations are in-memory values. Locking: compiler caches and
    runtime I/O retain their existing locking. ^nlintd-z5p5 ^nlintd-vneh ^nlintd-truth *)

type origin
(** Physical installed paths are separate from the unmodified compiler metadata. *)

type t = {
  path : string;
  info : Cmt_format.cmt_infos;
  builddir : string;
  origin : origin;
}

val ignored :
  caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > ->
  directory:string ->
  string list ->
  string list
(** Return entries ignored by Git in [directory], without following their symlinks.
    Missing Git/repository information excludes nothing. Explicit source or annotation
    arguments override Git ignores, nested-project boundaries and data-only
    classification; directory discovery (including the data-dependency inventory) honors
    Git ignores, and missing named paths remain errors even if ignored. *)

val workspace : caps:< Cap.fs_read ; .. > -> string -> string option
(** Workspace owning evidence for a source, directory or annotation. An annotation below
    [_build/default] is owned by that build tree, even below a nested project. Sources
    select the nearest project with their build copy, falling back to the nearest project
    when nothing was built. Nested projects compiled by an outer invocation therefore
    resolve evidence from the outer build root. This differs from the nearest
    [dune-project] used as a default-scan boundary. *)

val read : caps:< Cap.fs_read ; .. > -> string -> t
(** Build-tree rebasing, or public installed ownership from a unique adjacent
    [dune-package] (also one parent for a sublibrary). Installed sources and annotations
    must be uniquely listed, contained, non-symlinked plain inputs; absent PPX compiler
    inputs are unsupported. Compiler metadata is unchanged. *)

type target = Library | Executable
type membership = Built of target | Data_only | Not_built | Unknown

val membership : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> membership
(** Query Dune declarations, cached per build workspace. [describe workspace] answers for
    libraries/executables; [describe rules --recursive @check] supplies compilation
    sources omitted by workspace (notably [test]/[tests] on Dune 3.22). Dune resolves
    module sets and includes; existing annotations are never membership evidence. Absent
    compilation, a declared literal file, [source_tree] or [glob_files] dependency yields
    [Data_only]; [Not_built] means neither compiled nor consumed as data. Compilation
    always wins. Alias data declarations are read from Dune stanzas because
    [describe rules] omits alias actions. Data traversal stops at nested Dune projects and
    Git-ignored directories. A failed query or unrecognised format returns [Unknown],
    never an exclusion. *)

type generated = { path : string; producer : string option }

val generated_sources :
  caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > ->
  root:string ->
  (generated list, string) result
(** Declared compiled inputs without a checked-in counterpart. PP duplicates, Dune
    wrappers and nested projects are not returned. [producer] names the generating
    rule/copy stanza or executable/test empty-interface stanza and its source Dune file;
    [None] must be reported undecided. [Error] means the compilation inventory was
    unavailable, never an exclusion. *)

val find : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> t
(** Match the recorded source identity in local and enclosing build object directories,
    including qualified subdirectories. Missing or unreadable evidence raises a named
    failure; coverage is never inferred from existing annotations. ^nlint-2nwm. *)

val authored_source : caps:< Cap.fs_read ; .. > -> t -> string
(** Resolve and check a physical authored, declared-generated or installed source. A
    direct Dune-generated empty interface may return its actual [.pp.mli] compiler input
    only with a cached unique producer/compiler-owner proof, unchanged owner and
    configuration identities, matching source digest, empty typed interface and current
    CMI/import fingerprints. [generated_sources] must acquire that proof before checking;
    this fs-read-only operation never queries Dune. Explicit scans without the inventory
    remain unsupported. No authored or intermediate original may be replaced by
    empty-interface evidence. Missing input/inventory/provenance raises a named failure,
    never a silent pass. ^nlintd-truth ^nlintcov-q6n2 ^safe-y047 *)

val current : unit -> t option
(** The annotation whose checked compiler environment is currently configured;
    same-package helper resolution must not search unrelated build outputs. ^nlintc-du4v
*)

val setup : caps:< Cap.fs_read ; .. > -> t -> unit
(** Reset caches and initialize visible and hidden include paths in recorded order.
    Build-tree artifacts retain Dune private-CMI fallbacks. Installed artifacts map only
    their manifest-owned object directory and independently proved same-manifest siblings;
    the unavailable original cwd retains an empty search slot, never the invocation cwd.
    Every imported CMI must have the expected unit identity and fingerprint. *)

val rebuild_check : caps:< Cap.fs_read ; Cap.fork ; Cap.exec ; .. > -> string -> unit
(** Rebuild [@check] after the whole-repository inventory and before reading evidence.
    Explicit scans do not repair their supplied evidence. ^nlintcov-q6n2 *)

val source : t -> string
(** Resolve the physical source through its build directory or installed ownership,
    without rewriting the recorded compiler source filename. *)

val check : caps:< Cap.fs_read ; .. > -> source:string -> t -> unit
(** Check source digest, original/preprocessed freshness and complete payload. *)
