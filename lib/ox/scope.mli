(* ^nonce-r7mi ^nonce-4jzx: affine callback boundaries. *)
(** Cancellation and finalizers: Suspension: may suspend while starting fibers, joining
    scopes and running caller callbacks; delegated callback dispatch and Eio, Stdlib,
    Stdlib.List, Stdlib.Printexc operations retain their own behaviour. Cancellation:
    propagates from Eio switch checks, waits and caller callbacks unless run classifies
    it; delegated callback dispatch and Eio, Stdlib, Stdlib.List, Stdlib.Printexc
    operations retain their own behaviour. Finalizers: owned switches join their fibers,
    then run release hooks protected in reverse registration order; fork helpers register
    no release hook. Locking: no lock is held around caller callbacks. Cancellation
    safety: unsafe because progress is lost; started callbacks can have effects before
    interruption and are not rolled back. ^nlintd-a7oq ^nlintd-4ja0 *)

val run : (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) Exit.t
(** Boundaries that own their Eio switch. [run] awaits all child fibers and finalizers
    before returning. Cancellation is classified as [Interrupt]. The first failed child
    fiber is [Die], not [Finalizer]; if a typed failure also occurred, the two causes are
    [Concurrent]. A release failure is [Finalizer] or [Suppressed] after another failure.
    A defect reported by both the body and the switch is retained once. Eio exposes only
    the first switch cancellation reason before releases: further fiber failures mixed
    with release failures in an [Eio.Exn.Multiple] cannot be distinguished and may be
    classified as finalizer failures. Cancellation: classified as Cause.Interrupt rather
    than raised, including cancellation during cleanup. Cancellation safety: unsafe
    because progress is lost; callback effects before interruption remain. ^nlintd-a7oq *)

val classify : exn -> Printexc.raw_backtrace -> 'e Cause.t
(** Internal classification also usable by concurrency combinators. Pure. *)

type 'e t
(** A supervised scope whose typed failures have type ['e]. It is a view of one Eio
    switch: its forks are ordinary Eio fibers and the switch is available through
    {!switch}. *)

type ('a, 'e) fork
(** A fork started by {!fork_error}: a promise of the fork's [result]. *)

val supervised_error : sw:Eio.Switch.t -> ('e t -> ('a, 'e) result) -> ('a, 'e) result
(** [supervised_error ~sw body] runs [body] in a fresh Eio switch (a child of the caller's
    cancellation context) and returns its result. The first [Error e] from the body or
    from any {!fork_error} ends the scope: every other fiber is cancelled and awaited, and
    the result is [Error e] (later errors are dropped; the first one wins).

    An exception in the body or in any fork ends the scope the same way and is raised
    unchanged after the other fibers are cancelled and awaited; Eio drops the losers'
    cancellations in favour of it, and [Scope.run] classifies it as a defect. Cancelling
    the caller cancels the scope and every fork and propagates as cancellation, never as
    an [Error]. When the body returns [Ok] the scope still waits for its non-daemon forks
    (Eio's rule); daemon forks are cancelled when the body and every such fork have
    finished. Releases registered on {!switch} run after all forks finished.

    [sw] is the caller's switch: it is checked ([Invalid_argument] if finished, the
    cancellation if cancelled) and the scope owns nothing on it.

    @raise Invalid_argument if [sw] is finished. *)

val fork_error : 'e t -> (unit -> ('a, 'e) result) @ once -> ('a, 'e) fork
(** [fork_error scope f] starts [f] as a supervised fiber. [Ok] is the fork's outcome,
    joinable with {!await}; [Error e] ends the scope with [e] as {!supervised_error}
    describes. If the scope is already ending the fiber is not started (Eio's rule).

    The delegated Eio fork raises Invalid_argument if the scope's switch is finished or
    belongs to another domain. *)

val fork : 'e t -> (unit -> unit) @ once -> unit
(** [fork scope f] starts a plain fiber that cannot fail typed; an exception in it ends
    the scope, and its return value is not inspected.

    The delegated Eio fork raises Invalid_argument if the scope's switch is finished or
    belongs to another domain. *)

val fork_daemon : 'e t -> (unit -> unit) @ once -> unit
(** Like {!fork} but the scope does not wait for it: it is cancelled when the body and the
    non-daemon forks have finished (Eio's [fork_daemon] split, unchanged).

    The delegated Eio fork raises Invalid_argument if the scope's switch is finished or
    belongs to another domain. *)

val fork_error_daemon : 'e t -> (unit -> (unit, 'e) result) @ once -> unit
(** A daemon whose [Error e] ends the scope like {!fork_error}'s; [Ok ()] just ends the
    daemon and leaves the scope running. {!Concurrent.with_background} is this.

    The delegated Eio fork raises Invalid_argument if the scope's switch is finished or
    belongs to another domain. *)

val await : ('a, 'e) fork -> ('a, 'e) result
(** The fork's [result]. If the scope ends before the fork settles (its own failure, a
    sibling's, or cancellation) the awaiting fiber is cancelled like any other.
    Suspension: may suspend until the promise resolves. Cancellation: propagates from
    Eio.Promise.await. Cancellation safety: safe to re-run; waiting does not consume the
    promise result. Finalizers: none are registered by this call. Locking: no lock is held
    by this wrapper; promise synchronisation is delegated to Eio. ^nlintd-a7oq *)

val on_release : 'e t -> (unit -> unit) @ once -> unit
(** [on_release scope release] transfers an affine callback to the scope's switch.
    Eio runs releases protected, after forks finish, in reverse registration order.
    A finished switch runs [release] immediately under cancellation protection,
    then raises [Invalid_argument] if it returned normally. Suspension: may suspend
    only in an immediate release callback. Cancellation: protected throughout; Eio
    protects immediate release, and registration adds no cancellation check.
    Finalizers: registers [release] exactly once; no callback is retried. Locking: Eio
    locks registration but holds no lock around [release]. Affine ownership does not
    require the caller to register a release. ^nonce-4jzx

    @raise Invalid_argument if the switch is finished and immediate release returns.
    @raise Eio.Switch.Release_error if release raises during immediate registration on
      a finished switch; Eio wraps the release exception. *)

module Spawner : sig
  type 'e scope := 'e t

  type 'e t
  (** The permission to start fibers in one scope later, after the code that holds
      it has returned: a Service that forks after [create] names a ['e Spawner.t] in
      its deps. It is global and storable, keeps the scope's error type, and gives
      no access to the switch. A spawner of a finished scope refuses like the scope
      itself. ^nspawn-lhyg *)

  val fork : 'e t -> (unit -> unit) @ once -> unit
  (** {!Scope.fork} through the spawner. The delegated Eio fork raises
      Invalid_argument if the scope's switch is finished or belongs to another domain. *)

  val fork_daemon : 'e t -> (unit -> unit) @ once -> unit
  (** {!Scope.fork_daemon} through the spawner. The delegated Eio fork raises
      Invalid_argument if the scope's switch is finished or belongs to another domain. *)

  val fork_error : 'e t -> (unit -> ('a, 'e) result) @ once -> ('a, 'e) fork
  (** {!Scope.fork_error} through the spawner; the fork's [Error] ends the scope. The delegated Eio fork raises
      Invalid_argument if the scope's switch is finished or belongs to another domain. *)

  val fork_error_daemon : 'e t -> (unit -> (unit, 'e) result) @ once -> unit
  (** {!Scope.fork_error_daemon} through the spawner. The delegated Eio fork raises
      Invalid_argument if the scope's switch is finished or belongs to another domain. *)

  val on_release : 'e t -> (unit -> unit) @ once -> unit
  (** {!Scope.on_release} through the spawner. *)
end

val spawner : 'e t -> 'e Spawner.t
(** [spawner t] is [t]'s fork authority, to store in a Service's deps.
    Suspension: never suspends. Cancellation: not a cancellation point.
    Finalizers: none are registered. Locking: no lock is acquired. ^nspawn-lhyg *)

val switch : 'e t -> Eio.Switch.t
(** The scope's Eio switch, for [Eio.Switch.on_release] and other Eio APIs. Suspension:
    never suspends; this call only reads or constructs OCaml values. Cancellation: not a
    cancellation point; this call performs no Eio cancellation check. Finalizers: none are
    registered by this call; existing resource ownership is unchanged. Locking: no lock is
    acquired by this call. ^nlintd-a7oq *)

val exit_on_error : (('e -> exn) -> 'a) -> ('a, 'e) result
(** Building block for {!Concurrent}; prefer {!supervised_error}. [exit_on_error f] runs
    [f ended]; a fiber running inside [f] ends it with [raise (ended e)], which Eio
    propagates as any exception (cancelling and awaiting its siblings when raised through
    a switch, [Fiber.both], [Fiber.any], ...), and the result is [Error e] for the first
    [e] passed to [ended]. The returned exception is private to this call; if [ended]
    outlives [f] and is raised elsewhere it surfaces as a defect. Exceptions other than
    [ended]'s propagate unchanged, and cancellation of the caller wins over the error. *)
