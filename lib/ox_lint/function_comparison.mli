open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** Reject resolved Stdlib structural comparisons at directly known function types.
    Requires checked compiler evidence configured by [Artifact.setup]. Missing compiler
    dependencies propagate as evidence failures, never clean decisions. Suspension: never
    suspends during iterator construction; synchronous filesystem and compiler work may
    block the domain; operations delegate to Stdlib, Ox_caps, Paths, Env, Envaux, Ctype,
    Longident and Path and their higher-order callbacks; capability object method dispatch
    depends on the supplied provider; running returned visitors and [emit] depends on
    caller code. Cancellation: not a cancellation point during iterator construction;
    operations delegate to Stdlib, Ox_caps, Paths, Env, Envaux, Ctype, Longident and Path
    and their higher-order callbacks; capability object method dispatch depends on the
    supplied provider; running returned visitors and [emit] depends on caller code.
    Finalizers: no hook is registered; traversal state is an in-memory value. Locking:
    compiler synchronization is delegated; each iterator owns mutable state and must not
    be shared across simultaneous walks. *)
