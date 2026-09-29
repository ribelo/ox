val run : (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) Exit.t
(** Boundaries that own their Eio switch. [run] awaits all child fibers and finalizers
    before returning. Cancellation is classified as [Interrupt]. The first failed child
    fiber is [Die], not [Finalizer]; if a typed failure also occurred, the two causes are
    [Concurrent]. A release failure is [Finalizer] or [Suppressed] after another failure.
    A defect reported by both the body and the switch is retained once. Eio exposes only
    the first switch cancellation reason before releases: further fiber failures mixed
    with release failures in an [Eio.Exn.Multiple] cannot be distinguished and may be
    classified as finalizer failures. *)

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
    cancellation if cancelled) and the scope owns nothing on it. *)

val fork_error : 'e t -> (unit -> ('a, 'e) result) -> ('a, 'e) fork
(** [fork_error scope f] starts [f] as a supervised fiber. [Ok] is the fork's outcome,
    joinable with {!await}; [Error e] ends the scope with [e] as {!supervised_error}
    describes. If the scope is already ending the fiber is not started (Eio's rule). *)

val fork : 'e t -> (unit -> unit) -> unit
(** [fork scope f] starts a plain fiber that cannot fail typed; an exception in it ends
    the scope, and its return value is not inspected. *)

val fork_daemon : 'e t -> (unit -> unit) -> unit
(** Like {!fork} but the scope does not wait for it: it is cancelled when the body and the
    non-daemon forks have finished (Eio's [fork_daemon] split, unchanged). *)

val fork_error_daemon : 'e t -> (unit -> (unit, 'e) result) -> unit
(** A daemon whose [Error e] ends the scope like {!fork_error}'s; [Ok ()] just ends the
    daemon and leaves the scope running. {!Concurrent.with_background} is this. *)

val await : ('a, 'e) fork -> ('a, 'e) result
(** The fork's [result]. If the scope ends before the fork settles (its own failure, a
    sibling's, or cancellation) the awaiting fiber is cancelled like any other. *)

val switch : 'e t -> Eio.Switch.t
(** The scope's Eio switch, for [Eio.Switch.on_release] and other Eio APIs. *)

val exit_on_error : (('e -> exn) -> 'a) -> ('a, 'e) result
(** Building block for {!Concurrent}; prefer {!supervised_error}. [exit_on_error f] runs
    [f ended]; a fiber running inside [f] ends it with [raise (ended e)], which Eio
    propagates as any exception (cancelling and awaiting its siblings when raised through
    a switch, [Fiber.both], [Fiber.any], ...), and the result is [Error e] for the first
    [e] passed to [ended]. The returned exception is private to this call; if [ended]
    outlives [f] and is raised elsewhere it surfaces as a defect. Exceptions other than
    [ended]'s propagate unchanged, and cancellation of the caller wins over the error. *)
