(** Direct-style SQLite runner. A switch owns all opened handles.

    Cancellation and finalizers: Suspension: may suspend waiting for Eio mutexes,
    a pool lease, shutdown's condition, a timeout or caller callbacks; SQLite native
    calls may block the domain; delegated callback dispatch and Eio.Mutex, Eio.Pool, Ox_caps.Cap_unix, Stdlib, Stdlib.Int, Stdlib.List, Stdlib.Mutex, Stdlib.Option, Stdlib.Printexc operations retain their own behaviour. Cancellation: propagates Eio.Cancel.Cancelled from these waits and caller
    callbacks; configured deadlines return [Error `Timeout]; delegated callback dispatch and Eio.Mutex, Eio.Pool, Ox_caps.Cap_unix, Stdlib, Stdlib.Int, Stdlib.List, Stdlib.Mutex, Stdlib.Option, Stdlib.Printexc operations retain their own behaviour; a defect during lease/autocommit restoration or protected active-count cleanup propagates wrapped by Fun.Finally_raised. Finalizers: every lease
    restores autocommit or closes an unusable connection, decrements its active count
    protected and returns the lease even on cancellation. Switch release shuts the
    pool down and closes its handles. Locking: state updates use protected Eio mutex
    sections, not a lock spanning caller code; a lease is exclusive and SQLite uses
    native mutexes, including across row-fold callbacks. Cancellation safety: unsafe
    because progress is lost; completed SQL and caller effects are not rolled back
    by cancellation, except the database portion inside with_transaction.
    ^nlintd-a7oq ^nlintd-4ja0 *)
type error = [ `Ox_sql of Types.sql_error | `Pool_shutdown | `Timeout ]
type pool
type tx
type 'kind runner
type t = pool runner

(** [caps] is the clock authority each new handle captures (^inncap-b8ts). *)
val create :
  caps:< Ox_caps.Cap.time ; .. > ->
  sw:Eio.Switch.t ->
  ?clock:Eio.Time.Mono.ty Eio.Time.Mono.t ->
  ?default_timeout:Ox.Duration.t ->
  ?max_size:int ->
  Sqlite.config ->
  (t, error) result
(** Open the first connection and register switch-owned shutdown. [clock] measures
    configured deadlines with native monotonic time; [caps] retains wall-clock
    authority for connection diagnostic timestamps. Without [clock], timeout options
    are not enforced. ^safe-p9cw ^safe-8peq ^safe-5a9k

    Eio runs shutdown
    protected if registration finds the switch already finished, then raises; the
    opened connection is closed before that raise. ^nlintd-a7oq ^nlintd-raises

    @raise Invalid_argument if [sw] is finished.

    Eio.Switch.Release_error denotes a failed release callback on a switch owned by a delegated operation. ^nlintd-truth *)

val shutdown : t -> (unit, error) result
(** Internal Assert_failure guards the pool-vs-transaction runner invariant; the
    abstract pool phantom kind excludes a Transaction runner here. ^nlintd-truth

    Eio.Mutex.Poisoned denotes an internal mutex poisoned by a prior failed protected
    guarded mutation; that defect propagates rather than returning a pool error.
    ^nlintd-truth *)

module Typed : sig
  val select : ?timeout:Ox.Duration.t -> 'kind runner -> 'a Dsl.Compiled.select -> ('a list, error) result
  val returning : ?timeout:Ox.Duration.t -> 'kind runner -> 'a Dsl.Compiled.returning -> ('a list, error) result
  val fold_select : ?timeout:Ox.Duration.t -> 'kind runner -> 'row Dsl.Compiled.select -> init:'a -> f:('a -> 'row -> 'a) -> ('a, error) result
  val execute_compiled : ?timeout:Ox.Duration.t -> 'kind runner -> Dsl.Compiled.change -> (int, error) result
  val run_schema : ?timeout:Ox.Duration.t -> 'kind runner -> Dsl.Compiled.schema -> (unit, error) result
end
module Raw : sig
  val query : ?timeout:Ox.Duration.t -> 'kind runner -> string -> Value.t list -> (Row.t list, error) result
  val fold : ?timeout:Ox.Duration.t -> 'kind runner -> string -> Value.t list -> init:'a -> f:('a -> Row.t -> 'a) -> ('a, error) result
  val execute : ?timeout:Ox.Duration.t -> 'kind runner -> string -> Value.t list -> (int, error) result
  val execute_script : ?timeout:Ox.Duration.t -> 'kind runner -> string -> (unit, error) result
  val with_connection : 'kind runner -> (Sqlite.db @ local -> ('a, error) result) -> ('a, error) result
end
val with_transaction : ?timeout:Ox.Duration.t -> t -> (tx runner -> ('a, error) result) -> ('a, error) result
(** Internal Assert_failure guards the pool-vs-transaction runner invariant; the
    abstract pool phantom kind excludes a Transaction runner here. ^nlintd-truth *)
