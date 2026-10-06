open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Detect concrete compiler-identified shielded Eio nontermination: await_cancel and
    run_server without a stop promise. An authenticated finite inner deadline bounds its
    callback; protection nested inside that deadline does not. Promise.await, native
    settlement and opaque cleanup are not classified as indefinite work. This is not a
    general termination or physical-settlement certificate. Local aliases and executed
    callback/helper bodies are bounded to 32 and 128 steps. Inconsistent compiler value
    identity is rejected through [undecided]. Call only after [Artifact.check] and
    [Artifact.setup] on fresh compiler-matched annotations.

    Suspension: never suspends in Eio itself; synchronous work may block the domain;
    operations delegate to Stdlib, Env, Longident, Path and Ox_caps; capability object
    method dispatch depends on the supplied provider. Cancellation: not a cancellation
    point in Eio itself; operations delegate to Stdlib, Env, Longident, Path and Ox_caps;
    capability object method dispatch depends on the supplied provider. Finalizers: none
    registered. Locking: no new locks; compiler caches retain their existing locking.
    Returned visitors invoke the supplied callbacks. Raises: Assert_failure from compiler
    metadata, and exceptions from supplied callbacks. ^safe-ctc4 ^safe-vj9b ^safe-tcqo *)
