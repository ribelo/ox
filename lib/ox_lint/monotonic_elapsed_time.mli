open Ocaml_common
open Ox_caps

val check :
  caps:< Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Compiler-identity checks for wall-clock subtraction/comparison and relative delays.
    Run only after Artifact.check and Artifact.setup. Suspension: never suspends in Eio
    itself; synchronous compiler environment reconstruction may block; operations delegate
    to Stdlib, Ox_caps, Env, Envaux, Longident and Path and their higher-order callbacks;
    capability object method dispatch depends on the supplied provider; running returned
    visitors depends on caller code. Cancellation: not a cancellation point in Eio itself;
    operations delegate to Stdlib, Ox_caps, Env, Envaux, Longident and Path and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider; running returned visitors depends on caller code. Cancellation safety: safe
    to re-run with fresh callbacks. Finalizers: none are registered. Locking: compiler
    cache locking is unchanged. *)
