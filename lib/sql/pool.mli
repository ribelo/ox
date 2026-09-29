(** Direct-style SQLite runner. A switch owns all opened handles. *)
type error = [ `Ox_sql of Types.sql_error | `Pool_shutdown | `Timeout ]
type pool
type tx
type 'kind runner
type t = pool runner

val create : sw:Eio.Switch.t -> ?clock:[`Clock of float] Eio.Time.clock -> ?default_timeout:Ox.Duration.t -> ?max_size:int -> Sqlite.config -> (t, error) result
val shutdown : t -> (unit, error) result

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
