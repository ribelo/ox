(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }
val run : Eio.Mutex.t -> owned @ local unique -> int
(** Suspension: may suspend while acquiring the supplied mutex; the callback only reads the owned value.
    Cancellation: depends on Eio.Mutex.use_rw for acquisition and callback delivery; acquisition can propagate cancellation and the entered callback is unprotected and only reads the owned integer.
    Finalizers: no switch hook is registered; the provider releases the mutex after the entered callback and poisons it if the callback raises.
    Locking: the supplied mutex spans the owned-value read and is released before return.
    Cancellation safety: safe to re-run with a fresh owned value because cancelled acquisition has not entered the read-only callback or committed a data change. *)
