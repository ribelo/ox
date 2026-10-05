open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Report disposal, not correctness of count use. Suspension: never suspends itself
    during construction; dependency behavior is delegated to Env lookups/normalization,
    Longident parsing, Stdlib collections and lazy evidence, and capability object method
    dispatch; compiler reads may block. Cancellation: not a cancellation point itself
    during construction; dependency behavior is delegated to Env lookups/normalization,
    Longident parsing, Stdlib collections and lazy evidence, and capability object method
    dispatch. Walking the returned iterator delegates callback effects to caller [emit].
    Finalizers: none are registered. Locking: each iterator owns mutable state and must be
    walked serially. Cancellation safety: unsafe because progress is lost if an iterator
    walk aborts. Raises: missing supported operation evidence raises [Invalid_argument];
    compiler evidence failures and caller [emit] exceptions propagate unchanged;
    dependency exception behavior is delegated to Env, Longident, Stdlib collections/lazy
    evidence and capability object method dispatch. ^safe-jwwj ^safe-y047 *)
