open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Check authenticated acquisitions against handle-specific local release evidence.

    Cancellation and finalizers: Suspension: never suspends in visitor-owned operations;
    operations delegated to Env, Longident and Stdlib, object method dispatch, and
    supplied callbacks retain their own suspension behaviour. Synchronous compiler-context
    loading may block the domain. Cancellation: not a cancellation point in visitor-owned
    operations; operations delegated to Env, Longident and Stdlib, object method dispatch,
    and supplied callbacks retain their own cancellation behaviour. Finalizers: no
    resource/finalizer ownership is transferred. Locking: no analysis-owned locks;
    compiler caches retain their existing behaviour. Compiler-evidence failures and
    callback defects propagate; unresolved provenance calls [undecided]. Cancellation
    safety: unsafe because progress is lost; callbacks may have emitted observations
    before a defect propagates. ^safe-cank ^safe-763t *)
