val timer : unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio.Time.sleep and Eio_main.run. Cancellation:
    depends on those Eio operations. Cancellation safety: unsafe because progress is lost.
    Finalizers: delegated to Eio_main.run. Locking: delegated to Eio. *)

val native : pool:Ox_blocking.Pool.t -> unit -> unit
(** ^safe-r5ye: Suspension: may suspend in Eio_main.run and Ox_blocking.run; callback
    execution is delegated to Ox_blocking.run; the native sleep may block its worker and
    continues after caller cancellation until physical completion. Cancellation: depends
    on those Eio operations. Cancellation safety: unsafe because progress is lost; native
    work cannot be rolled back. Finalizers: Eio_main.run owns runtime cleanup; the
    supplied pool is borrowed. Callback invocation and physical completion are delegated
    to Ox_blocking.run and the supplied pool. Locking: delegated to the supplied pool. *)

val harmless : unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio_main.run, not Unix.getpid. Cancellation:
    depends on Eio_main.run. Cancellation safety: unsafe because progress is lost.
    Finalizers: delegated to Eio_main.run. Locking: delegated to Eio. *)

val non_eio : unit -> unit
(** ^safe-9ved: Suspension: never suspends cooperatively; Thread.delay blocks the calling
    domain. Cancellation: no Eio cancellation point is added. Cancellation safety: unsafe
    because elapsed time cannot be rolled back. Finalizers: none are registered. Locking:
    delegated to Thread.delay. *)

val counting_native : pool:Ox_blocking.Pool.t -> Semaphore.Counting.t -> unit -> unit
(** ^safe-r5ye: Suspension: may suspend in Eio_main.run and Ox_blocking.run; callback
    execution is delegated to Ox_blocking.run; acquiring the native semaphore may block
    its worker. Cancellation: depends on those Eio operations. Cancellation safety: unsafe
    because progress is lost; consumed permits are not restored. Finalizers: Eio_main.run
    owns runtime cleanup; the pool and semaphore are borrowed. A started native
    acquisition survives caller cancellation and retains access to the semaphore until
    physical completion; draining pool shutdown waits for that completion. Callback
    invocation and physical completion are delegated to Ox_blocking.run and the supplied
    pool. Locking: delegated to the supplied pool and native semaphore. *)

val counting_outside : Semaphore.Counting.t -> unit -> unit
(** ^safe-9ved: Suspension: never suspends cooperatively; acquisition may block the
    calling domain. Cancellation: no Eio cancellation point is added. Cancellation safety:
    unsafe because progress is lost; consumed permits are not restored. Finalizers: none
    are registered. Locking: delegated to the supplied native semaphore. *)

val counting_owner : Eio.Semaphore.t -> unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio.Semaphore.acquire and Eio_main.run.
    Cancellation: depends on those Eio operations. Cancellation safety: unsafe because
    progress is lost; consumed permits are not restored. Finalizers: Eio_main.run owns
    runtime cleanup; the semaphore is borrowed. Locking: delegated to the supplied Eio
    semaphore. *)
