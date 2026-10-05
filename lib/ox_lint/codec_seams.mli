open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Artifact.t ->
  unit
(** Check the finite audited domain designations and exact interface-local [@@@ox.domain]
    opt-ins. Run only after annotation freshness/import checks and [Artifact.setup]. Raw
    published positions are findings; missing construction, provider, alias or module
    evidence is nonwaivable undecided. No schema is invented and abstraction alone
    establishes no validation claim.

    Suspension: never suspends itself; synchronous compiler/filesystem work may block;
    delegates to Stdlib, Ox_caps, Artifact, Syntax, Paths, Unix.lstat, Unix.realpath, Env,
    Envaux, Cmt_format, Cmi_format, Ctype, Mtype, Btype, Load_path, Compilation_unit,
    Import_info, Ident, Path, Types, Parse, Lexer, Docstrings, Longident, Location,
    Tast_iterator and caller callbacks; object method dispatch depends on the supplied
    capability provider. Cancellation: not a cancellation point itself; delegates to
    Stdlib, Ox_caps, Artifact, Syntax, Paths, Unix.lstat, Unix.realpath, Env, Envaux,
    Cmt_format, Cmi_format, Ctype, Mtype, Btype, Load_path, Compilation_unit, Import_info,
    Ident, Path, Types, Parse, Lexer, Docstrings, Longident, Location, Tast_iterator and
    caller callbacks; object method dispatch depends on the supplied provider. Finalizers:
    no hook registered; compiler input channels are closed by their readers. Locking:
    compiler caches retain their existing synchronization; use serially.

    @raise Failure if an unhandled compiler/helper defect or caller callback raises it. *)
