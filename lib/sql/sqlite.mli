(** Low-allocation SQLite connector.

    This module is deliberately connector-level: explicit database handles,
    prepared statements, bind operations, stepping, and typed column reads.
    Higher-level query construction belongs to a separate experiment. *)

type db
(** SQLite database handle. *)

type stmt
(** Prepared statement. A statement keeps its database handle reachable. *)

type rc = private int
(** SQLite result code. *)

type open_mode =
  | Read_only
  | Read_write
  | Read_write_create

type journal_mode =
  [ `Delete
  | `Truncate
  | `Persist
  | `Memory
  | `Wal
  | `Off
  ]

type synchronous =
  [ `Extra
  | `Full
  | `Normal
  | `Off
  ]

type config = {
  path : string;
  mode : open_mode;
  busy_timeout_ms : int option;
  foreign_keys : bool;
  journal_mode : journal_mode option;
  synchronous : synchronous option;
  cache_size : int option;
}

type transaction_mode =
  | Deferred
  | Immediate
  | Exclusive

type error = {
  global_ operation : string;
  code : rc;
  global_ message : string;
}

exception Error of error

val pp_error : Format.formatter -> error -> unit
val global_error : error @ local -> error @@ portable

val ok : rc
val row : rc
val done_ : rc
val misuse : rc
val range : rc
val constraint_ : rc
val busy : rc
val locked : rc
val interrupt_ : rc

val sqlite_integer : int
val sqlite_float : int
val sqlite_text : int
val sqlite_blob : int
val sqlite_null : int

val rc_code : rc -> int
val rc_name : rc -> string @@ portable
val rc_equal : rc -> rc -> bool @@ portable

val open_ : ?mode:open_mode -> string -> db
(** Open a SQLite database path. The default mode is [Read_write_create].
    [":memory:"] opens an in-memory database. *)

val open_memory : unit -> db
val default_config : string -> config
val memory_config : unit -> config
val open_with_config : config -> db
val with_db : config -> (db -> 'a) -> 'a

val close : db -> rc @@ portable
(** Close a database handle. Statements may still be finalized after closing. *)

val prepare_result : db @ local -> string -> (stmt, error) result @ local @@ portable
val prepare : db @ local -> string -> stmt @ local @@ portable
val prepare_owned_result : db -> string -> (stmt, error) result @@ portable
val prepare_owned : db -> string -> stmt
(** Prepare SQL or raise {!Error}. *)

val finalize : stmt @ local -> rc @@ portable
val reset : stmt @ local -> rc
val clear_bindings : stmt @ local -> rc
val bind_parameter_count : stmt @ local -> int

val bind_null : stmt @ local -> int -> rc @@ portable
val bind_int64 : stmt @ local -> int -> int64 -> rc @@ portable
val bind_int : stmt @ local -> int -> int -> rc @@ portable
val bind_text : stmt @ local -> int -> string -> rc @@ portable
val bind_float : stmt @ local -> int -> float -> rc @@ portable
val bind_blob : stmt @ local -> int -> bytes -> rc @@ portable
val bind_zeroblob : stmt @ local -> int -> int -> rc

val step : stmt @ local -> rc @@ portable

val column_int64 : stmt @ local -> int -> int64 @@ portable
val column_int : stmt @ local -> int -> int
(** Read an INTEGER column as an OCaml [int]. Raises [Invalid_argument] if the
    SQLite 64-bit integer is outside the OCaml [int] range; use
    {!column_int64} for full-width SQLite integers. *)
val column_text : stmt @ local -> int -> string @@ portable
val column_float : stmt @ local -> int -> float @@ portable
val column_blob : stmt @ local -> int -> bytes @@ portable
val column_is_null : stmt @ local -> int -> bool
val column_count : stmt @ local -> int @@ portable
val column_name : stmt @ local -> int -> string @@ portable
val column_type_code : stmt @ local -> int -> int @@ portable
val data_count : stmt @ local -> int
val statement_sql : stmt @ local -> string
val expanded_sql : stmt @ local -> string
val statement_readonly : stmt @ local -> bool
val statement_busy : stmt @ local -> bool

val changes : db @ local -> int @@ portable
val total_changes : db @ local -> int
val last_insert_rowid : db @ local -> int64
val error_code : db @ local -> rc
val extended_error_code : db @ local -> int
val error_message : db @ local -> string
val autocommit : db @ local -> bool @@ portable
val database_readonly : db @ local -> string -> bool
val busy_timeout : db @ local -> int -> rc
val interrupt : db @ local -> unit
(** Interrupt active native statements. SQLite does not retain this request
    while no statement is running; use [Cancellation] for operation-scoped
    cancellation that must survive native statement startup. *)

module Cancellation : sig
  type t

  val create : db -> t
  (** A fresh, sticky cancellation token for one database operation. *)

  val request : t -> unit
  (** Thread-safe: interrupt active SQLite work and retain cancellation for
      native work that has not started yet. Safe before [with_handler]. *)

  val with_handler : t -> (unit -> 'a) -> 'a
  (** Install a native progress callback for the dynamic extent of the worker.
      The caller must exclusively own the connection until this returns; scopes
      must not overlap or nest on one connection. Cancellation is never reset.
      The handler is removed on both return and exception, before lease reuse.
      Long native statements observe cancellation every 1000 VM instructions. *)
end
val is_interrupted : db @ local -> bool
val is_closed : db @ local -> bool @@ portable
(** Whether {!close} already closed this handle. A closed handle is never
    reopened, and connector calls on it either report {!error} results or
    return no usable connection state. *)
val complete : string -> bool

val check : db @ local -> operation:string -> rc -> (unit, error) result @@ portable
val check_exn : db @ local -> operation:string -> rc -> unit
(** Convert a result code to a structured error using the database's current
    SQLite diagnostic message. *)

val exec_result : db @ local -> string -> (unit, error) result @@ portable
val exec : db @ local -> string -> unit
(** Execute a statement that returns no rows. [exec] raises {!Error}. *)

val exec_script_result : db @ local -> string -> (unit, error) result @@ portable
val exec_script : db @ local -> string -> unit
(** Execute one or more SQL statements and ignore result rows. *)

val begin_transaction_result :
  ?mode:transaction_mode -> db @ local -> (unit, error) result @@ portable
val begin_transaction : ?mode:transaction_mode -> db @ local -> unit
val commit_result : db @ local -> (unit, error) result @@ portable
val commit : db @ local -> unit
val rollback_result : db @ local -> (unit, error) result @@ portable
val rollback : db @ local -> unit
val with_transaction :
  ?mode:transaction_mode ->
  db ->
  (db @ local -> ('a, error) result) @ local ->
  ('a, error) Ox_sql_dsl.transaction_outcome
(** Synchronous SQLite transaction using {!Ox_sql_dsl.transaction}. The
    callback returns [result]; wrap a successful bare value as [Ok]. *)

val savepoint_result : db @ local -> string -> (unit, error) result
val savepoint : db @ local -> string -> unit
val release_result : db @ local -> string -> (unit, error) result
val release : db @ local -> string -> unit
val rollback_to_result : db @ local -> string -> (unit, error) result
val rollback_to : db @ local -> string -> unit

val enable_load_extension : db @ local -> bool -> rc
val load_extension_result : db @ local -> string -> (unit, error) result
val load_extension : db @ local -> string -> unit

val backup_to_path_result : db @ local -> string -> (unit, error) result
val backup_to_path : db @ local -> string -> unit
val restore_from_path_result : db @ local -> string -> (unit, error) result
val restore_from_path : db @ local -> string -> unit

val query_one_int_result : db @ local -> string -> (int, error) result
val query_one_int : db @ local -> string -> int
(** Small typed convenience used by tests and smoke probes. *)

module Config : sig
  type mode = open_mode =
    | Read_only
    | Read_write
    | Read_write_create

  type t = config = {
    path : string;
    mode : open_mode;
    busy_timeout_ms : int option;
    foreign_keys : bool;
    journal_mode : journal_mode option;
    synchronous : synchronous option;
    cache_size : int option;
  }

  val default : string -> t
  val in_memory : unit -> t
end

module Error : sig
  type t = error = {
    global_ operation : string;
    code : rc;
    global_ message : string;
  }

  val pp : Format.formatter -> t -> unit
  val to_string : t -> string
end

module Testing : sig
  val with_db : Config.t -> (db -> ('a, string) result) -> ('a, string) result
end
