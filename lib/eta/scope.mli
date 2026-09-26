(** Boundaries that own their Eio switch. [run] awaits all child fibers and
    finalizers before returning. Cancellation is classified as [Interrupt];
    a failing release after a typed/body failure is [Suppressed]. *)
val run : (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) Exit.t
val classify : exn -> Printexc.raw_backtrace -> 'e Cause.t
(** Internal classification also usable by concurrency combinators. Pure. *)
