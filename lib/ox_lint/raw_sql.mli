open Ocaml_common

val message : string

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Detect supported dynamic string construction at genuine raw SQL sinks. This bounded
    rule does not validate arbitrary SQL or report opaque text.

    Cancellation and finalizers: Suspension: never suspends in Eio itself; compiler
    metadata loading may block; operations delegate to Env, Path, Paths, Stdlib and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider; returned visitors and emit callbacks depend on caller code. Cancellation:
    not a cancellation point itself; operations delegate to Env, Path, Paths, Stdlib and
    their higher-order callbacks; capability object method dispatch depends on the
    supplied provider; returned visitors and emit callbacks depend on caller code.
    Finalizers: none registered. Locking: compiler caches retain their existing locking;
    each iterator owns mutable traversal state and must not be shared across simultaneous
    walks. Cancellation safety: safe to re-run; creating a fresh iterator emits nothing;
    returned visitors and emit callbacks retain caller-dependent behaviour. ^safe-8pmk
    ^safe-p1m1 ^safe-iq5u *)
