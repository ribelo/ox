open Ocaml_common
open Ox_caps

val check :
  caps:< Cap.fs_read ; .. > ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  Tast_iterator.iterator
(** Check the finite execution-context contract against a fresh artifact configured by
    [Artifact.setup]. Suspension: may suspend through supplied capability-provider methods
    during construction and traversal, and to caller [emit] and [undecided] callbacks;
    compiler reads may block the domain. No direct Eio operation is added. Cancellation:
    depends on the supplied provider and diagnostic callbacks. Diagnostic callback
    exceptions propagate with an already-emitted prefix; selected native-forwarding
    evidence failures are classified unresolved. No direct Eio cancellation point is
    added. Finalizers: no resource or finalizer is owned or escapes; compiler reads
    delegate channel cleanup to the compiler libraries. Locking: no checker lock is
    acquired; compiler caches retain their existing locking. Cancellation safety: unsafe
    because progress is lost; diagnostics and compiler cache changes are not rolled back
    when caller code interrupts traversal. ^safe-9ved ^safe-r5ye ^safe-ohen *)
