val fractional : unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio_main.run; Unix.sleepf blocks its domain.
    Cancellation: depends on Eio_main.run, not the native wait. Cancellation safety:
    unsafe because elapsed time cannot be rolled back. Finalizers: delegated to
    Eio_main.run. Locking: delegated to the runtime and native wait. *)

val integer : unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio_main.run; Unix.sleep blocks its domain.
    Cancellation: depends on Eio_main.run, not the native wait. Cancellation safety:
    unsafe because elapsed time cannot be rolled back. Finalizers: delegated to
    Eio_main.run. Locking: delegated to the runtime and native wait. *)

val thread : unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio_main.run; Thread.delay blocks its domain.
    Cancellation: depends on Eio_main.run, not the native wait. Cancellation safety:
    unsafe because elapsed time cannot be rolled back. Finalizers: delegated to
    Eio_main.run. Locking: delegated to the runtime and native wait. *)

val counting : Semaphore.Counting.t -> unit -> unit
(** ^safe-9ved: Suspension: may suspend in Eio_main.run; native acquisition may block
    its domain. Cancellation: depends on Eio_main.run, not the native wait. Cancellation
    safety: unsafe because consumed permits are not restored. Finalizers: Eio_main.run
    owns runtime cleanup; the semaphore is borrowed. Locking: delegated to the runtime
    and supplied native semaphore. *)
