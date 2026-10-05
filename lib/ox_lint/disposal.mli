val discarded_result :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  (Ocaml_common.Location.t -> unit) ->
  Ocaml_common.Tast_iterator.iterator
(** Legacy standard-ignore and whole wildcard-binding detection. Named discards and
    explicit result matches are accepted. Does not prove handling through unknown
    higher-order calls or inspect other compilation units. Reads compiler interfaces
    through the supplied authority; missing dependencies fail closed; unresolved required
    standard identities raise Failure. Suspension: never suspends in Eio itself;
    synchronous compiler/filesystem work may block; operations delegate to Stdlib, Paths,
    Env, Envaux, Longident and Path; capability object method dispatch depends on the
    supplied provider; running returned visitors depends on compiler traversal and caller
    callbacks. Cancellation: not a cancellation point in Eio itself; operations delegate
    to Stdlib, Paths, Env, Envaux, Longident and Path; capability object method dispatch
    depends on the supplied provider; running returned visitors depends on compiler
    traversal and caller callbacks. Finalizers: none registered. Locking: compiler caches
    keep their existing locking. ^safe-1bc7 ^safe-s6km ^safe-3osb *)
