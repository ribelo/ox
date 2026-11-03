(** Branded guarded data, single-domain, over [Eio.Mutex]. Shaped after
    Jane Street's [Capsule.Mutex] and [Await.Mutex], which do not install on
    5.4.0+ox (ADR-0010).

    A mutex has a fresh brand ['k], hidden by {!packed}. An owner module
    allocates its mutable state internally, gives it the brand of the mutex
    that guards it, and exports operations that require a ['k Access.t]. Such
    an access exists only inside a critical section and is [local], so it
    cannot be stored, returned or captured by a fork. Reading the state
    without the lock, with another mutex's access, or after the section ends
    does not compile. A generic payload getter would leak an alias and is not
    an ownership boundary, so this module has none. ^ncrit-ihf2 ^ncrit-1px5

    Cancellation and finalizers:
    Suspension: may suspend while acquiring the Eio mutex, and inside a
    waiting section's callback.
    Cancellation: propagates Eio.Cancel.Cancelled from acquisition, with the
    lock not held, and from a waiting section's callback, after releasing the
    lock.
    Finalizers: no switch hook is registered; the lock is released when the
    callback returns or raises.
    Locking: the mutex is held across the callback and only across it;
    sections do not nest on one mutex, and a re-entrant section waits for ever.
    Cancellation safety: unsafe because progress is lost when a waiting
    section is cancelled part-way; the owner's state keeps whatever the
    callback had already changed. ^nlintd-a7oq *)

type 'k t
(** A mutex with brand ['k]. *)

type packed = P : 'k t -> packed  (** The fresh brand of a new mutex. *)

module Access : sig
  type 'k t
  (** The right to the state of brand ['k]; only a critical section makes
      one. *)
end

val create : unit -> packed
(** [create ()] is an unlocked mutex with a fresh brand.
    Suspension: never suspends; it only allocates.
    Cancellation: not a cancellation point; it performs no Eio check.
    Finalizers: none are registered.
    Locking: no lock is acquired. *)

val with_access : 'k t -> ('k Access.t @ local -> 'b) @ local once unyielding -> 'b
(** [with_access t f] runs [f] under [t] for short bookkeeping. [f] is
    [unyielding]: it cannot capture a yielding value. Suspension inside it is
    refused by the type only once Ox owns the suspension surface (row 71,
    [suspend-token]); until then a raw Eio wait inside [f] still compiles.
    [f] runs at most once and is not entered if acquisition is cancelled.
    ^ncrit-9sfw *)

val with_access_waiting : 'k t -> ('k Access.t @ local -> 'b) @ local once -> 'b
(** [with_access_waiting t f] runs [f] under [t] for a section that waits
    legitimately, such as a transport write under the lock or a condition
    wait. Other fibers wanting [t] wait for the whole section. ^ncrit-9sfw *)
