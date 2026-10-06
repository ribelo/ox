open Ocaml_common

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Check executed native callbacks and owner callbacks established by authenticated Eio
    entry points. Owner sleep/join/counting-semaphore waits and native Eio operations are
    the selected defect classes; descriptor read/write state is outside this catalogue.
    [emit] reports a resolved context defect; [undecided] reports selected known Eio
    values escaping an opaque scope, candidate defaults, or exhausted local candidate
    evidence. Opaque ordinary calls without a selected candidate are outside this
    catalogue, not certified NoEio. Both receive the call location and a message naming
    its worker-entry origin. Returned/stored closures are not executed unless a local
    invocation is established. Import/freshness errors are not caught.

    Suspension: may suspend through supplied capability-provider methods and caller [emit]
    and [undecided] callbacks; compiler/filesystem work may block the domain. No direct
    Eio operation is added. Cancellation: depends on the supplied provider and diagnostic
    callbacks; no Eio cancellation check is added by this visitor. Cancellation safety:
    unsafe because progress is lost if caller code aborts traversal. Finalizers: none are
    registered by the visitor. Locking: compiler-cache synchronization is delegated; each
    visitor owns mutable traversal state and must not be shared across simultaneous walks.
*)
