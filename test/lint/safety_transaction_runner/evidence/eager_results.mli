(* ^safe-j6t8 ^safe-m5sp: native compiler-authenticated payload controls. *)
module P = Ox_sql.Pool
module Shadow : sig
  type int = { runner : P.tx P.runner }
end
type scalar = int
val clean : consume:(scalar -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val direct : sink:(P.tx P.runner -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val closure : sink:((unit -> int) -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val tuple : sink:(P.tx P.runner * int -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val record : sink:(Shadow.int -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val produced : produce:(P.tx P.runner -> int) -> consume:(int -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val nested_wrong : consume:(int -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)

val result : sink:((P.tx P.runner, unit) result -> unit) -> P.t -> (unit, P.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and callback finalizers; the caller retains pool ownership. Locking: delegated pool
    leases and callbacks retain their locking. Cancellation safety: unsafe because
    progress is lost; SQL or callback effects may already have completed. ^safe-tlyw *)
