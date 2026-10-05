(* ^safe-ldtb ^safe-fr73: native MI-first ordinary callback root calibration. *)
val switch : Ox_sql.Pool.t -> (Ox_sql.Row.t list, Ox_sql.Pool.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool, Eio or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and Eio or callback finalizers; supplied pool/switch ownership remains with the caller.
    Locking: delegated pool leases and callbacks retain their locking. Cancellation safety:
    unsafe because progress is lost; committed SQL or callback effects may already have
    completed. ^safe-tlyw *)
val main : Ox_sql.Pool.t -> (Ox_sql.Row.t list, Ox_sql.Pool.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    delegated Ox_sql.Pool, Eio or caller operations; native SQLite may block the domain.
    Cancellation: delegated operations and callbacks retain their behaviour; cancellation
    and callback defects may propagate. Finalizers: delegate transaction/lease cleanup
    and Eio or callback finalizers; supplied pool/switch ownership remains with the caller.
    Locking: delegated pool leases and callbacks retain their locking. Cancellation safety:
    unsafe because progress is lost; committed SQL or callback effects may already have
    completed. ^safe-tlyw *)
