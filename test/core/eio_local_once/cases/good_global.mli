(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
val run : Eio.Mutex.t -> (unit -> int) -> int
(** Suspension: may suspend while acquiring the mutex or invoking caller callback [f].
    Cancellation: depends on caller callback [f]; its first two invocations are shielded, but mutex acquisition and the final invocation are not protected.
    Finalizers: no switch hook is registered; the provider unlocks after its mutex callback succeeds and poisons the mutex if that callback raises.
    Locking: the second invocation holds the supplied mutex; the first and final invocations do not acquire it, and [f] may acquire its own locks.
    Cancellation safety: unsafe because progress is lost when an earlier invocation of [f] has committed effects before cancellation interrupts acquisition or the final invocation. *)
