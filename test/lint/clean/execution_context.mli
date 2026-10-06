val native : Ox_blocking.Pool.t -> (int, [ `Shutting_down ]) result
(** Suspension: may suspend in pool admission, completion and Eio hooks; callback
    invocation is delegated to Ox_blocking and caller code. Cancellation: propagates
    caller cancellation; already started native work continues. Cancellation safety:
    unsafe because progress is lost. Finalizers: no switch finalizer is registered; the
    borrowed pool owns physical completion. Locking: pool synchronization is internal; no
    pool lock is held while caller hooks run. *)

val hooks : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
(** Suspension: may suspend in pool admission, completion and Eio hooks; callback
    invocation is delegated to Ox_blocking and caller code. Cancellation: propagates
    caller cancellation; already started native work continues. Cancellation safety:
    unsafe because progress is lost. Finalizers: no switch finalizer is registered; the
    borrowed pool owns physical completion. Locking: pool synchronization is internal; no
    pool lock is held while caller hooks run. *)

val dormant : Ox_blocking.Pool.t -> (unit -> unit, [ `Shutting_down ]) result
(** Suspension: may suspend in pool admission, completion and Eio hooks; callback
    invocation is delegated to Ox_blocking and caller code. Cancellation: propagates
    caller cancellation; already started native work continues. Cancellation safety:
    unsafe because progress is lost. Finalizers: no switch finalizer is registered; the
    borrowed pool owns physical completion. Locking: pool synchronization is internal; no
    pool lock is held while caller hooks run. *)
