(** Boundaries that own their Eio switch. [run] awaits all child fibers and
    finalizers before returning. Cancellation is classified as [Interrupt].
    The first failed child fiber is [Die], not [Finalizer]; if a typed failure
    also occurred, the two causes are [Concurrent]. A release failure is [Finalizer]
    or [Suppressed] after another failure. A defect reported by both the body
    and the switch is retained once. Eio exposes only the first switch
    cancellation reason before releases: further fiber failures mixed with
    release failures in an [Eio.Exn.Multiple] cannot be distinguished and may
    be classified as finalizer failures. *)
val run : (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) Exit.t
val classify : exn -> Printexc.raw_backtrace -> 'e Cause.t
(** Internal classification also usable by concurrency combinators. Pure. *)
