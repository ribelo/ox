type t

val create : unit -> t

val with_read :
  io:Io.t @ yielding -> t ->
  (unit -> 'a) @ local once yielding -> 'a
(** [with_read t f] runs [f] with a shared read lease. New readers wait while a
    writer is waiting or holding the write lease. Cancellation or an exception
    from [f] releases the lease. *)

val with_write :
  io:Io.t @ yielding ->
  ?on_waiting:(unit -> (unit, 'e) result) @ local unyielding ->
  t ->
  (unit -> ('a, 'e) result) @ local once yielding ->
  ('a, 'e) result
(** [with_write t f] runs [f] while holding the exclusive write lease. [f] runs
    with the gate mutex held so readers cannot observe partial publication.
    Cancellation or an exception from [f] releases the lease. [on_waiting] is
    called after registering a writer blocked by active readers, with cleanup
    installed and the mutex held; it must not suspend. *)
