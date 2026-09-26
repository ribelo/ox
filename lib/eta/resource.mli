(** Register release on the supplied switch in acquisition order; Eio runs
    releases in reverse order, even on cancellation. A raised release defect
    is classified as [Finalizer] or [Suppressed] by enclosing [Scope.run]. *)
val acquire_release : sw:Eio.Switch.t -> acquire:(unit -> ('r, 'e) result) -> release:('r -> unit) -> ('r, 'e) result
