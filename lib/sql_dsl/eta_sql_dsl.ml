let quote_text value =
  let len = String.length value in
  let extra_quotes = ref 0 in
  for i = 0 to len - 1 do
    let ch = String.unsafe_get value i in
    if Char.equal ch '\000' then
      invalid_arg "Eta_sql_dsl.quote_text: embedded NUL is not a SQL literal";
    if Char.equal ch '\'' then incr extra_quotes
  done;
  let out = Bytes.create (len + !extra_quotes + 2) in
  Bytes.unsafe_set out 0 '\'';
  let j = ref 1 in
  for i = 0 to len - 1 do
    let ch = String.unsafe_get value i in
    Bytes.unsafe_set out !j ch;
    incr j;
    if Char.equal ch '\'' then (
      Bytes.unsafe_set out !j '\'';
      incr j)
  done;
  Bytes.unsafe_set out !j '\'';
  Bytes.unsafe_to_string out

let quote_blob value =
  let hex = "0123456789ABCDEF" in
  let len = Bytes.length value in
  let out = Bytes.create ((len * 2) + 3) in
  Bytes.unsafe_set out 0 'X';
  Bytes.unsafe_set out 1 '\'';
  for i = 0 to len - 1 do
    let byte = Char.code (Bytes.unsafe_get value i) in
    Bytes.unsafe_set out ((i * 2) + 2) (String.unsafe_get hex (byte lsr 4));
    Bytes.unsafe_set out ((i * 2) + 3) (String.unsafe_get hex (byte land 0xF))
  done;
  Bytes.unsafe_set out ((len * 2) + 2) '\'';
  Bytes.unsafe_to_string out

let quote_float value =
  if Float.is_finite value then Printf.sprintf "%.17g" value
  else invalid_arg "Eta_sql_dsl.quote_float: non-finite float is not a SQL literal"

type 'error callback_failure =
  | Returned of 'error
  | Raised of exn * Printexc.raw_backtrace

type transaction_phase =
  | Begin
  | Body
  | Commit

type 'error rollback_outcome =
  | Rollback_not_attempted
  | Rollback_succeeded
  | Rollback_failed of 'error callback_failure

type 'error transaction_failure = {
  phase : transaction_phase;
  primary : 'error callback_failure;
  rollback : 'error rollback_outcome;
}

type ('a, 'error) transaction_outcome =
  | Committed of 'a
  | Failed of 'error transaction_failure

let invoke @ portable = fun (f @ local) ->
  match f () with
  | Ok value -> `Ok value
  | Error err -> `Returned err
  | exception exn ->
      let backtrace = Printexc.get_raw_backtrace () in
      `Raised (exn, backtrace)

let run_rollback @ portable = fun rollback (resource @ local) ->
  match invoke (fun () -> rollback resource) with
  | `Ok () -> Rollback_succeeded
  | `Returned err -> Rollback_failed (Returned err)
  | `Raised (exn, backtrace) -> Rollback_failed (Raised (exn, backtrace))

let failed @ portable = fun phase primary rollback -> Failed { phase; primary; rollback }

let transaction @ portable = fun ~begin_ ~commit ~rollback (resource @ local) (f @ local) ->
  match invoke (fun () -> begin_ resource) with
  | `Returned err ->
      failed Begin (Returned err) Rollback_not_attempted
  | `Raised (exn, backtrace) ->
      failed Begin (Raised (exn, backtrace)) Rollback_not_attempted
  | `Ok () -> (
      match invoke (fun () -> f resource) with
      | `Returned err ->
          failed Body (Returned err) (run_rollback rollback resource)
      | `Raised (exn, backtrace) ->
          failed Body
            (Raised (exn, backtrace))
            (run_rollback rollback resource)
      | `Ok value -> (
          match invoke (fun () -> commit resource) with
          | `Ok () -> Committed value
          | `Returned err ->
              failed Commit (Returned err) (run_rollback rollback resource)
          | `Raised (exn, backtrace) ->
              failed Commit
                (Raised (exn, backtrace))
                (run_rollback rollback resource)))

module Row = struct
  module type VALUE = sig
    type t

    val to_int : t -> int option
    val to_int64 : t -> int64 option
    val to_string_value : t -> string option
    val to_bool : t -> bool option
    val to_float : t -> float option
    val to_bytes : t -> bytes option
    val to_string : t -> string
    val equal : t -> t -> bool
  end

  module Make (Value : VALUE) = struct
    type value = Value.t
    type t = (string * value) list

    let get field row =
      let rec loop = function
        | [] -> None
        | (name, value) :: rest ->
            if String.equal name field then Some value else loop rest
      in
      loop row

    let fields row =
      List.map fst row

    let int field row = Option.bind (get field row) Value.to_int
    let int64 field row = Option.bind (get field row) Value.to_int64
    let string field row = Option.bind (get field row) Value.to_string_value
    let bool field row = Option.bind (get field row) Value.to_bool
    let float field row = Option.bind (get field row) Value.to_float
    let bytes field row = Option.bind (get field row) Value.to_bytes

    let to_string row =
      row
      |> List.map (fun (field, value) -> field ^ "=" ^ Value.to_string value)
      |> String.concat ", "

    let equal left right =
      List.length left = List.length right
      && List.for_all2
           (fun (left_field, left_value) (right_field, right_value) ->
             String.equal left_field right_field
             && Value.equal left_value right_value)
           left right
  end
end

module type BACKEND = sig
  type value
  type row
  type error

  exception Error of error

  type 'a typ = {
    value : ('a -> value);
    decode : (row @ local -> int -> 'a);
    sql_type : string;
  }
  (* The DSL needs a uniform primitive surface, but codec behavior belongs to
     the backend: SQL type names, row storage, NULL checks, and coercions differ
     across SQLite cursors and materialized row backends. *)

  val int : int typ
  val int64 : int64 typ
  val bool : bool typ
  val float : float typ
  val text : string typ
  val nullable : 'a typ -> 'a option typ
  val invalid_query : string -> error
  val module_name : string
  val value_to_string : value -> string
  val value_to_sql_literal : value -> string
end

module type S = sig
  type value
  type row
  type error

  type 'a typ

  val int : int typ
  val int64 : int64 typ
  val bool : bool typ
  val float : float typ
  val text : string typ
  val nullable : 'a typ -> 'a option typ
  type param = Param : 'a typ * 'a -> param

  module Numeric : sig
    type 'a t

    val int : int t
    val int64 : int64 t
    val float : float t
  end

  module Compiled : sig
    (** Generated SQL artifacts produced by the typed DSL.

        These values are intentionally inspectable for drivers and diagnostics.
        They preserve generated SQL, parameters, projection width, and decoders;
        they do not make the DSL a closed safety boundary. Code that constructs
        compiled records directly or routes through raw execution APIs owns SQL
        validity and decoder correctness outside the builder's type checks. *)

    type 'a select
    type 'a returning
    type change
    type schema

    val value_of_param : param -> value
    val select_sql : 'a select -> string
    val select_width : 'a select -> int
    (** Number of SQL columns projected by this select. *)

    val select_params : 'a select -> value list
    val select_decode : 'a select -> row @ local -> 'a
    val returning_sql : 'a returning -> string
    val returning_params : 'a returning -> value list
    val returning_decode : 'a returning -> row @ local -> 'a
    val change_sql : change -> string
    val change_params : change -> value list
    val schema_sql : schema -> string
  end

  type 'table table
  type ('table, 'a) column

  module Table : sig
    type 'table t = 'table table

    module Make (_ : sig
      val name : string
    end) : sig
      type table

      val table : table t
      val column : string -> 'a typ -> (table, 'a) column
    end

    val name : 'table t -> string
    val alias : 'table t -> string -> 'table t
    (** [alias table name] renders [table AS name] in sources and qualifies
        columns created from the alias with [name]. *)

    val column : 'table t -> string -> 'a typ -> ('table, 'a) column
    (** Create a column value bound to a table value, including aliases. *)
  end

  module Column : sig
    type ('table, 'a) t = ('table, 'a) column
    type 'table any
    (** A column whose value type is erased while its phantom table identity is
        kept. Heterogeneous column lists - composite indexes, conflict targets,
        and conflict-update sets - are written as [any] lists, so a list may mix
        value types while every entry still belongs to one table. *)

    val any : ('table, 'a) t -> 'table any
    (** [any column] erases the value type of [column] while keeping its table
        identity. Erasure is construction-only: an [any] value is rendered but
        never bound as a parameter, so the typed/raw boundary is unchanged. *)
    val name : (_, _) t -> string
    val table_name : (_, _) t -> string
  end

  module Expr : sig
    type ('scope, 'a) t
    (** A typed SQL expression visible in ['scope] and decoding/rendering as ['a]. *)

    val true_ : ('scope, bool) t
    (** SQL true predicate. *)
    val false_ : ('scope, bool) t
    (** SQL false predicate. *)
    val lit : 'a typ -> 'a -> ('scope, 'a) t
    (** Parameterized literal with an explicit SQL type. *)
    val int_lit : int -> ('scope, int) t
    (** Parameterized integer literal. *)
    val int64_lit : int64 -> ('scope, int64) t
    (** Parameterized 64-bit integer literal. *)
    val float_lit : float -> ('scope, float) t
    (** Parameterized float literal. *)
    val text_lit : string -> ('scope, string) t
    (** Parameterized text literal. *)
    val bool_lit : bool -> ('scope, bool) t
    (** Parameterized boolean literal. *)
    val col : ('scope, 'a) column -> ('scope, 'a) t
    (** Treat a visible column as a typed expression. *)
    val eq : ('scope, 'a) column -> 'a -> ('scope, bool) t
    (** Column equals literal. *)
    val ne : ('scope, 'a) column -> 'a -> ('scope, bool) t
    (** Column does not equal literal. *)
    val gt : ('scope, 'a) column -> 'a -> ('scope, bool) t
    (** Column is greater than literal. *)
    val ge : ('scope, 'a) column -> 'a -> ('scope, bool) t
    (** Column is greater than or equal to literal. *)
    val lt : ('scope, 'a) column -> 'a -> ('scope, bool) t
    (** Column is less than literal. *)
    val le : ('scope, 'a) column -> 'a -> ('scope, bool) t
    (** Column is less than or equal to literal. *)
    val like : ?escape:char -> ('scope, string) column -> string -> ('scope, bool) t
    (** Text column matches a SQL LIKE pattern, optionally with an escape
        character. *)
    val contains_pattern : string -> string * char
    (** LIKE pattern and escape character matching a literal substring. *)
    val escape_char : string -> char
    (** Read one escape character from text; raises [Invalid_argument] otherwise. *)
    val eq_expr : ('scope, 'a) t -> ('scope, 'a) t -> ('scope, bool) t
    (** Expression equals expression. *)
    val ne_expr : ('scope, 'a) t -> ('scope, 'a) t -> ('scope, bool) t
    (** Expression does not equal expression. *)
    val gt_expr : ('scope, 'a) t -> ('scope, 'a) t -> ('scope, bool) t
    (** Expression is greater than expression. *)
    val ge_expr : ('scope, 'a) t -> ('scope, 'a) t -> ('scope, bool) t
    (** Expression is greater than or equal to expression. *)
    val lt_expr : ('scope, 'a) t -> ('scope, 'a) t -> ('scope, bool) t
    (** Expression is less than expression. *)
    val le_expr : ('scope, 'a) t -> ('scope, 'a) t -> ('scope, bool) t
    (** Expression is less than or equal to expression. *)
    val eq_col : ('scope, 'a) column -> ('scope, 'a) column -> ('scope, bool) t
    (** Column equals column. *)
    val gt_col : ('scope, 'a) column -> ('scope, 'a) column -> ('scope, bool) t
    (** Column is greater than column. *)
    val ge_col : ('scope, 'a) column -> ('scope, 'a) column -> ('scope, bool) t
    (** Column is greater than or equal to column. *)
    val lt_col : ('scope, 'a) column -> ('scope, 'a) column -> ('scope, bool) t
    (** Column is less than column. *)
    val le_col : ('scope, 'a) column -> ('scope, 'a) column -> ('scope, bool) t
    (** Column is less than or equal to column. *)
    val add : 'a Numeric.t -> ('scope, 'a) t -> ('scope, 'a) t -> ('scope, 'a) t
    (** SQL addition over numeric same-typed expressions. *)
    val sub : 'a Numeric.t -> ('scope, 'a) t -> ('scope, 'a) t -> ('scope, 'a) t
    (** SQL subtraction over numeric same-typed expressions. *)
    val mul : 'a Numeric.t -> ('scope, 'a) t -> ('scope, 'a) t -> ('scope, 'a) t
    (** SQL multiplication over numeric same-typed expressions. *)
    val div : 'a Numeric.t -> ('scope, 'a) t -> ('scope, 'a) t -> ('scope, 'a) t
    (** SQL division over numeric same-typed expressions. *)
    val is_null : ('scope, 'a option) column -> ('scope, bool) t
    (** Nullable column is NULL. *)
    val is_not_null : ('scope, 'a option) column -> ('scope, bool) t
    (** Nullable column is not NULL. *)
    val between : ('scope, 'a) column -> 'a -> 'a -> ('scope, bool) t
    (** Column lies between two literal bounds. *)
    val in_values : ('scope, 'a) column -> 'a list -> ('scope, bool) t
    (** Column is in a non-empty literal list. *)
    val in_select : ('scope, 'a) column -> 'a Compiled.select -> ('scope, bool) t
    (** Column is in a typed subquery result. *)
    val exists : _ Compiled.select -> ('scope, bool) t
    (** SQL EXISTS predicate for a compiled subquery. *)
    val count : unit -> ('scope, int) t
    (** COUNT-star aggregate expression. *)
    val sum_int : ('scope, int) column -> ('scope, int option) t
    (** SUM aggregate over an integer column. SQLite returns NULL for an empty input. *)
    val sum_float : ('scope, float) column -> ('scope, float option) t
    (** SUM aggregate over a float column. SQLite returns NULL for an empty input. *)
    val avg : 'a Numeric.t -> ('scope, 'a) column -> ('scope, float option) t
    (** AVG aggregate over a numeric SQLite column. SQLite returns NULL for an empty input. *)
    val min : ('scope, 'a) column -> ('scope, 'a option) t
    (** MIN aggregate preserving the column type. SQLite returns NULL for an empty input. *)
    val max : ('scope, 'a) column -> ('scope, 'a option) t
    (** MAX aggregate preserving the column type. SQLite returns NULL for an empty input. *)
    val sum_int_nullable :
      ('scope, int option) column -> ('scope, int option) t
    (** SUM aggregate over a nullable integer column. NULL inputs are ignored, and
        an all-NULL group decodes as [None]. *)
    val sum_float_nullable :
      ('scope, float option) column -> ('scope, float option) t
    (** SUM aggregate over a nullable float column. NULL inputs are ignored, and an
        all-NULL group decodes as [None]. *)
    val avg_nullable :
      'a Numeric.t ->
      ('scope, 'a option) column ->
      ('scope, float option) t
    (** AVG aggregate over a nullable numeric column. NULL inputs are ignored, and
        an all-NULL group decodes as [None]. *)
    val min_nullable : ('scope, 'a option) column -> ('scope, 'a option) t
    (** MIN aggregate over a nullable column, preserving the declared type. *)
    val max_nullable : ('scope, 'a option) column -> ('scope, 'a option) t
    (** MAX aggregate over a nullable column, preserving the declared type. *)
    val coalesce : ('scope, 'a option) t -> 'a -> ('scope, 'a) t
    (** COALESCE over a nullable expression and a non-null fallback. The result is
        non-nullable, so a NULL result fails loudly instead of decoding as a value. *)
    val case :
      (('scope, bool) t * ('scope, 'a) t) list ->
      default:('scope, 'a) t ->
      ('scope, 'a) t
    (** CASE WHEN expression with same-typed result branches. *)
    val and_ : ('scope, bool) t -> ('scope, bool) t -> ('scope, bool) t
    (** Boolean AND. *)
    val or_ : ('scope, bool) t -> ('scope, bool) t -> ('scope, bool) t
    (** Boolean OR. *)
    val not_ : ('scope, bool) t -> ('scope, bool) t
    (** Boolean NOT. *)
  end

  module Projection : sig
    type ('scope, 'a) t
    (** A SELECT projection visible in ['scope] and decoding one output value ['a]. *)

    val one : ('scope, 'a) column -> ('scope, 'a) t
    (** Project one visible column. *)
    val expr : ?as_:string -> ('scope, 'a) Expr.t -> ('scope, 'a) t
    (** Project any typed expression, optionally assigning a SQL alias. *)
    val t2 : ('scope, 'a) t -> ('scope, 'b) t -> ('scope, 'a * 'b) t
    (** Combine two projections into a pair. *)
    val t3 :
      ('scope, 'a) t ->
      ('scope, 'b) t ->
      ('scope, 'c) t ->
      ('scope, 'a * 'b * 'c) t
    val count : ?as_:string -> unit -> ('scope, int) t
    (** Project COUNT-star. *)
    val sum_int : ?as_:string -> ('scope, int) column -> ('scope, int option) t
    (** Project SUM over an integer column. *)
    val sum_float : ?as_:string -> ('scope, float) column -> ('scope, float option) t
    (** Project SUM over a float column. *)
    val avg :
      ?as_:string ->
      'a Numeric.t ->
      ('scope, 'a) column ->
      ('scope, float option) t
    (** Project AVG over a numeric SQLite column. *)
    val min : ?as_:string -> ('scope, 'a) column -> ('scope, 'a option) t
    (** Project MIN preserving the column type. *)
    val max : ?as_:string -> ('scope, 'a) column -> ('scope, 'a option) t
    (** Project MAX preserving the column type. *)
    val sum_int_nullable :
      ?as_:string -> ('scope, int option) column -> ('scope, int option) t
    (** Project SUM over a nullable integer column. *)
    val sum_float_nullable :
      ?as_:string -> ('scope, float option) column -> ('scope, float option) t
    (** Project SUM over a nullable float column. *)
    val avg_nullable :
      ?as_:string ->
      'a Numeric.t ->
      ('scope, 'a option) column ->
      ('scope, float option) t
    (** Project AVG over a nullable numeric column. *)
    val min_nullable :
      ?as_:string -> ('scope, 'a option) column -> ('scope, 'a option) t
    (** Project MIN over a nullable column, preserving the declared type. *)
    val max_nullable :
      ?as_:string -> ('scope, 'a option) column -> ('scope, 'a option) t
    (** Project MAX over a nullable column, preserving the declared type. *)
    val row_number :
      ?as_:string ->
      ?partition_by:('scope, 'a) column list ->
      ?order_by:('scope, 'b) column ->
      unit ->
      ('scope, int) t
    (** Project ROW_NUMBER() with optional partition and order clauses. *)
    val t4 :
      ('scope, 'a) t ->
      ('scope, 'b) t ->
      ('scope, 'c) t ->
      ('scope, 'd) t ->
      ('scope, 'a * 'b * 'c * 'd) t
    val t5 :
      ('scope, 'a) t ->
      ('scope, 'b) t ->
      ('scope, 'c) t ->
      ('scope, 'd) t ->
      ('scope, 'e) t ->
      ('scope, 'a * 'b * 'c * 'd * 'e) t
    val t6 :
      ('scope, 'a) t ->
      ('scope, 'b) t ->
      ('scope, 'c) t ->
      ('scope, 'd) t ->
      ('scope, 'e) t ->
      ('scope, 'f) t ->
      ('scope, 'a * 'b * 'c * 'd * 'e * 'f) t
    val t7 :
      ('scope, 'a) t ->
      ('scope, 'b) t ->
      ('scope, 'c) t ->
      ('scope, 'd) t ->
      ('scope, 'e) t ->
      ('scope, 'f) t ->
      ('scope, 'g) t ->
      ('scope, 'a * 'b * 'c * 'd * 'e * 'f * 'g) t
    val t8 :
      ('scope, 'a) t ->
      ('scope, 'b) t ->
      ('scope, 'c) t ->
      ('scope, 'd) t ->
      ('scope, 'e) t ->
      ('scope, 'f) t ->
      ('scope, 'g) t ->
      ('scope, 'h) t ->
      ('scope, 'a * 'b * 'c * 'd * 'e * 'f * 'g * 'h) t
    val map : ('a -> 'b) -> ('scope, 'a) t -> ('scope, 'b) t
    (** Map the decoded value while preserving the SQL projection. *)
  end

  module Scope : sig
    type ('sub, 'super) contains
    (** Evidence that ['super] contains every table visible in ['sub]. *)

    val self : ('scope, 'scope) contains
    (** A scope contains itself. *)
    val left : ('sub, 'super) contains -> ('sub, 'super * 'added) contains
    (** If a scope is contained in the existing side, it is contained after a join. *)
    val right : ('added, 'existing * 'added) contains
    (** The newly joined table is contained on the right side of a join. *)
    val column :
      ('sub, 'super) contains -> ('sub, 'a) column -> ('super, 'a) column
    (** Promote a column only when containment evidence proves it is visible. *)
    val nullable_column :
      ('sub, 'super) contains -> ('sub, 'a) column -> ('super, 'a option) column
    (** Promote a column through scope evidence and decode SQL NULL as [None].
        Use this for columns from the nullable side of an outer join. *)
  end

  module Source : sig
    type 'scope t
    (** A FROM source with the phantom scope of all visible tables. *)

    val from : 'table table -> 'table t
    (** Start a source from one table. *)
    val join :
      ?op:[ `Inner | `Left ] ->
      on:('existing * 'added, bool) Expr.t ->
      'added table ->
      'existing t ->
      ('existing * 'added) t
    (** Join one table onto an existing source. [on] is checked against the
        enlarged scope and can reference both existing columns and the new table. *)
  end

  module Select : sig
    type ('scope, 'a) t

    val from : 'table table -> ('table, 'a) Projection.t -> ('table, 'a) t
    val from_source : 'scope Source.t -> ('scope, 'a) Projection.t -> ('scope, 'a) t
    val with_cte :
      name:string -> _ Compiled.select -> ('scope, 'a) t -> ('scope, 'a) t
    val distinct : ('scope, 'a) t -> ('scope, 'a) t
    val where : ('scope, bool) Expr.t -> ('scope, 'a) t -> ('scope, 'a) t
    val group_by : ('scope, 'b) column -> ('scope, 'a) t -> ('scope, 'a) t
    val group_by_many :
      ('scope, 'b) column list -> ('scope, 'a) t -> ('scope, 'a) t
    val having : ('scope, bool) Expr.t -> ('scope, 'a) t -> ('scope, 'a) t
    val order_by : ?desc:bool -> ('scope, 'b) column -> ('scope, 'a) t -> ('scope, 'a) t
    val limit : int -> ('scope, 'a) t -> ('scope, 'a) t
    val to_sql : (_, _) t -> string
    val compile : (_, 'a) t -> 'a Compiled.select
  end

  module Insert : sig
    type 'table t

    val into : 'table table -> 'table t
    val value : ('table, 'a) column -> 'a -> 'table t -> 'table t
    val on_conflict_do_nothing :
      'table Column.any list -> 'table t -> 'table t
    (** [on_conflict_do_nothing columns query] renders ON CONFLICT (columns) DO
        NOTHING. [columns] may mix value types but must belong to the insert's
        table. An empty [columns] is rejected with [Invalid_argument]. *)
    val on_conflict_update :
      'table Column.any list ->
      set:'table Column.any list ->
      'table t ->
      'table t
    (** [on_conflict_update columns ~set query] renders ON CONFLICT (columns) DO
        UPDATE SET, assigning every [set] column from [excluded]. Both lists may
        mix value types but must belong to the insert's table. An empty
        [columns] or [set] is rejected with [Invalid_argument]. *)
    val to_sql : _ t -> string
    val compile : _ t -> Compiled.change
    val returning : ('table, 'a) Projection.t -> 'table t -> 'a Compiled.returning
  end

  module Update : sig
    type 'table t

    val table : 'table table -> 'table t
    val set : ('table, 'a) column -> 'a -> 'table t -> 'table t
    val where : ('table, bool) Expr.t -> 'table t -> 'table t
    val to_sql : _ t -> string
    val compile : _ t -> Compiled.change
    val returning : ('table, 'a) Projection.t -> 'table t -> 'a Compiled.returning
  end

  module Delete : sig
    type 'table t

    val from : 'table table -> 'table t
    val where : ('table, bool) Expr.t -> 'table t -> 'table t
    val to_sql : _ t -> string
    val compile : _ t -> Compiled.change
    val returning : ('table, 'a) Projection.t -> 'table t -> 'a Compiled.returning
  end

  module Eta_schema : sig
    type referential_action =
      | Cascade
      | Restrict
      | Set_null
      | No_action
      | Set_default

    type reference
    type column_def
    type t

    val references :
      ?on_delete:referential_action ->
      ?on_update:referential_action ->
      (_, _) column ->
      reference
    val column :
      ?primary_key:bool ->
      ?not_null:bool ->
      ?unique:bool ->
      ?default:'a ->
      ?references:reference ->
      (_, 'a) column ->
      column_def
    val create_table : ?if_not_exists:bool -> 'table table -> column_def list -> t
    val drop_table : ?if_exists:bool -> 'table table -> t
    val create_index :
      ?unique:bool ->
      ?if_not_exists:bool ->
      name:string ->
      'table table ->
      'table Column.any list ->
      t
    (** [create_index ?unique ?if_not_exists ~name table columns] renders CREATE
        [UNIQUE] INDEX over [columns]. [columns] may mix value types but must
        belong to [table]. An empty [columns] is rejected with
        [Invalid_argument]. *)
    val to_sql : t -> string
    val compile : t -> Compiled.schema
  end

  val quote_ident : string -> string
  val params_to_values : param list -> value list
end

module Make = Eta_sql_dsl_query.Make
