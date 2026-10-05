open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Reports proved out-of-bounds constant reads in the supported literal horizon. Missing
    compiler dependencies propagate as evidence failures.

    Cancellation and finalizers: Suspension: never suspends in Eio itself; synchronous
    compiler filesystem work may block the domain; operations delegate to Stdlib, Ox_caps,
    Env, Envaux, Longident and Path and their higher-order callbacks; capability object
    method dispatch depends on the supplied provider; running returned visitors and the
    emit callback depends on caller code. Cancellation: not a cancellation point in Eio
    itself; operations delegate to Stdlib, Ox_caps, Env, Envaux, Longident and Path and
    their higher-order callbacks; capability object method dispatch depends on the
    supplied provider; running returned visitors and the emit callback depends on caller
    code; Failure reports unavailable standard compiler identities. Finalizers: no hook is
    registered; iterator state is an in-memory value. Locking: compiler and Stdlib
    synchronization are delegated; each iterator owns mutable traversal state and must not
    be shared across simultaneous walks. ^safe-m5sp ^safe-fr73 *)
