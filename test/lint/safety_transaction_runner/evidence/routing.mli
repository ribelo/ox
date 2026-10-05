val cases :
  opaque:(Ox_sql.Pool.t -> (unit, Ox_sql.Pool.error) result) ->
  schedule:((unit -> (Ox_sql.Row.t list, Ox_sql.Pool.error) result) -> unit) ->
  Ox_sql.Pool.t ->
  Ox_sql.Pool.t ->
  (unit -> (Ox_sql.Row.t list, Ox_sql.Pool.error) result, Ox_sql.Pool.error) result
(** Fixture-only SQL entry. Cancellation and finalizers: Suspension: may suspend through
    Ox_sql.Pool operations or caller callbacks; native SQLite calls may block the domain.
    Cancellation: depends on delegated Ox_sql.Pool, Eio and Stdlib operations and caller
    callbacks retain their behaviour; cancellation and callback defects may propagate.
    Finalizers: delegate to pool transaction/lease cleanup and callback finalizers; the
    caller retains pool/switch ownership. Locking: delegated pool leases and callbacks
    retain their locking. Cancellation safety: unsafe because progress is lost; SQL or
    callback effects outside the rollback boundary may already have completed. ^safe-tlyw
*)
