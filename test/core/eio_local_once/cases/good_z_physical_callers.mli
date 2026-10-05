(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
val run : Eio.Mutex.t -> int
(** Suspension: may suspend in the two mutex acquisitions delegated to [Good_mutex_local.run] and [Good_local_unprotected.run].
    Cancellation: propagates during either mutex acquisition; the protected reads are shielded, while the final unprotected callback only reads its owned integer.
    Finalizers: no switch hook is registered; each mutex helper releases its own acquisition before the next helper or return.
    Locking: the supplied mutex spans each mutex-helper read separately; the first protected read acquires no lock.
    Cancellation safety: safe to re-run because each call constructs fresh owned holders and the completed read-only callbacks commit no data change. *)
