type t
(** ^safe-sw86 ^safe-bt9f: private test driver, never an installed producer API. The real
    Eio native callback is submitted and held just before the production claim. *)

val arm : unit -> t
(** Suspension: never suspends. Cancellation: not a cancellation point. Finalizers: the
    test must call [unblock] even on failure. Locking: none. *)

val await_submitted : t -> unit
(** Suspension: may suspend until the real native callback has been submitted.
    Cancellation: propagates caller cancellation. Finalizers: none. Locking: none.
    Cancellation safety: safe to re-run because this only observes the submission. *)

val unblock : t -> unit
(** Suspension: never suspends. Cancellation: not a cancellation point. Finalizers:
    releases the private native gate. Locking: none. *)

val await_returned : t -> unit
(** Suspension: may suspend until the owner fiber returns from the real native call.
    Cancellation: propagates caller cancellation. Finalizers: none. Locking: none.
    Cancellation safety: safe to re-run because this only observes the native return. *)

module Eio_unix : sig
  val run_in_systhread : ?label:string -> (unit -> 'a) -> 'a
  (** Suspension: may suspend until the real native callback and private gate complete.
      Cancellation: propagates caller cancellation. Finalizers: publishes owner-side
      return. Locking: the submitted native callback waits on a private counting
      semaphore. Cancellation safety: unsafe because progress is lost while native work
      may continue. *)
end
