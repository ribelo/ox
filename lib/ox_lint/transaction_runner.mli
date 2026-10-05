open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Check resolved SQL operations in transaction callbacks using finite local identity
    evidence. Visitor outcomes belong to the caller; no findings are stored globally.

    Cancellation and finalizers: Suspension: never suspends in visitor-owned operations;
    operations delegated to Env, Longident and Stdlib, object method dispatch, and
    supplied callbacks retain their own suspension behaviour. Synchronous compiler-context
    loading may block the domain. Cancellation: not a cancellation point in visitor-owned
    operations; operations delegated to Env, Longident and Stdlib, object method dispatch,
    and supplied callbacks retain their own cancellation behaviour. Finalizers: no
    resource/finalizer ownership is transferred. Locking: no analysis-owned locks;
    compiler caches retain their existing behaviour. Compiler-evidence failures and
    callback defects propagate; ordinary unresolved routing calls [undecided].
    Cancellation safety: unsafe because progress is lost; callbacks may have emitted
    observations before a defect propagates. ^safe-fr73 *)
