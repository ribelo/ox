(* Independent solver control. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }
val protected : owned @ local unique -> int
val locked : Eio.Mutex.t -> owned @ local unique -> int
(** Suspension: may suspend while acquiring the supplied mutex; the callback only reads the owned value.
    Cancellation: propagates during mutex acquisition; only the entered read-only callback is shielded, not acquisition.
    Finalizers: no switch hook is registered; the provider releases the mutex after the entered callback.
    Locking: the supplied mutex spans the owned-value read and is released before return.
    Cancellation safety: safe to re-run with a fresh owned value because cancelled acquisition has not entered the read-only callback or committed a data change. *)
