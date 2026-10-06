val bound : 'a Ox_sql.Pool.runner -> string -> (int, Ox_sql.Pool.error) result
(** Cancellation and finalizers: Suspension: may suspend through delegated Ox_sql.Pool
    operations; native SQLite calls may block the domain; Ox_sql.Compiled, Ox_sql.Value
    and Stdlib operations retain their own behaviour. Cancellation: depends on delegated
    Ox_sql.Pool and caller operations retain their own behaviour; cancellation and defects
    may propagate. Finalizers: delegate to pool lease cleanup; the caller retains
    pool/switch ownership. Locking: delegated pool operations retain their locking.
    Cancellation safety: unsafe because progress is lost; completed SQL effects are not
    rolled back. ^safe-8pmk ^safe-p1m1 ^safe-iq5u *)

val generated :
  'a Ox_sql.Pool.runner -> Ox_sql.Compiled.schema -> (unit, Ox_sql.Pool.error) result
(** Cancellation and finalizers: Suspension: may suspend through delegated Ox_sql.Pool
    operations; native SQLite calls may block the domain; Ox_sql.Compiled, Ox_sql.Value
    and Stdlib operations retain their own behaviour. Cancellation: depends on delegated
    Ox_sql.Pool and caller operations retain their own behaviour; cancellation and defects
    may propagate. Finalizers: delegate to pool lease cleanup; the caller retains
    pool/switch ownership. Locking: delegated pool operations retain their locking.
    Cancellation safety: unsafe because progress is lost; completed SQL effects are not
    rolled back. ^safe-8pmk ^safe-p1m1 ^safe-iq5u *)
