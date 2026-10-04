type error = Sql_failure.error =
  | Sqlite of Sqlite.error
  | Pool_error of string
  | Invalid_query of string
  | Decode_error of {
      operation : string;
      message : string;
    }

val pp_error : Format.formatter -> error -> unit
val show_error : error -> string

type sql_error = error

type 'a typ = {
  value : ('a -> Value.t);
  decode : (Sqlite.stmt @ local -> int -> 'a);
  sql_type : string;
}

val int : int typ
val int64 : int64 typ
val text : string typ
val float : float typ
val blob : bytes typ
val bool : bool typ
val nullable : 'a typ -> 'a option typ

val sqlite_result : ('a, Sqlite.error) result -> ('a, error) result @@ portable
val check_sqlite : Sqlite.db @ local -> operation:string -> Sqlite.rc -> (unit, error) result @@ portable
val unexpected_sqlite_step : operation:string -> Sqlite.rc -> ('a, error) result @@ portable
val finalize_result : Sqlite.db @ local -> Sqlite.stmt @ local -> ('a, error) result -> ('a, error) result @@ portable
val bind_value : Sqlite.stmt @ local -> int -> Value.t -> Sqlite.rc @@ portable
val bind_dynamic_values : Sqlite.db @ local -> Sqlite.stmt @ local -> Value.t list -> (unit, error) result @@ portable
val with_dynamic_statement :
  Sqlite.db @ local ->
  string ->
  Value.t list ->
  (Sqlite.stmt @ local -> ('a, error) result) @ local ->
  ('a, error) result @@ portable
val read_dynamic_value : Sqlite.stmt @ local -> int -> Value.t @@ portable
val materialize_row : Sqlite.stmt @ local -> Row.t @@ portable
val query_dynamic : Sqlite.db @ local -> string -> Value.t list -> (Row.t list, error) result @@ portable
val execute_dynamic : Sqlite.db @ local -> string -> Value.t list -> (int, error) result @@ portable
