open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Inspect assertion conditions in checked compiler evidence. [emit] reports proved
    mutation/I/O; [undecided] names calls outside the finite evaluation horizon. Call
    [Artifact.setup] before running the visitor. Suspension: never suspends in Eio itself;
    synchronous compiler/filesystem work may block the domain; operations delegate to
    Stdlib, Ox_caps, Env, Envaux, Longident and Path and their higher-order callbacks;
    capability object method dispatch depends on the supplied provider; running the
    returned visitor depends on caller-provided [emit] and [undecided]. Cancellation: not
    a cancellation point in Eio itself; operations delegate to Stdlib, Ox_caps, Env,
    Envaux, Longident and Path and their higher-order callbacks; capability object method
    dispatch depends on the supplied provider; running the returned visitor depends on
    caller code. Finalizers: none are registered. Locking: compiler and Stdlib
    synchronization are delegated; each iterator owns mutable traversal state and must not
    be shared across simultaneous walks. ^safe-pcom ^safe-u7cx *)
