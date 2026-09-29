module type BACKEND = sig
  type 'a typ

  val module_name : string
  val sql_type : 'a typ -> string
  val literal : 'a typ -> 'a -> string
end

module Make
    (Backend : BACKEND)
    (Model : sig
      type 'table table = {
        table_name : string;
        quoted_table_name : string;
        from_sql : string;
        column_qualifier : string;
      }

      type ('table, 'a) column = {
        table_name : string;
        column_name : string;
        typ : 'a Backend.typ;
        quoted_column_name : string;
        qualified_column_name : string;
      }

      type 'table any
      (** A column whose value type is erased while its table identity is kept;
          heterogeneous column lists are written as [any] lists. *)

      val any_column_name : 'table any -> string
      (** Rendered column name of an erased column. *)

      type compiled_schema

      val quote_ident : string -> string
      val compiled_schema : string -> compiled_schema
    end) : sig
  type referential_action = Cascade | Restrict | Set_null | No_action | Set_default
  type reference
  type column_def
  type t

  val references :
    ?on_delete:referential_action ->
    ?on_update:referential_action ->
    (_, _) Model.column ->
    reference

  val column :
    ?primary_key:bool ->
    ?not_null:bool ->
    ?unique:bool ->
    ?default:'a ->
    ?references:reference ->
    (_, 'a) Model.column ->
    column_def

  val create_table : ?if_not_exists:bool -> 'table Model.table -> column_def list -> t
  val drop_table : ?if_exists:bool -> 'table Model.table -> t

  val create_index :
    ?unique:bool ->
    ?if_not_exists:bool ->
    name:string ->
    'table Model.table ->
    'table Model.any list ->
    t
  (** [create_index ?unique ?if_not_exists ~name table columns] renders CREATE [UNIQUE]
      INDEX over [columns]. [columns] may mix value types but must belong to [table]. An
      empty [columns] is rejected with [Invalid_argument]. *)

  val to_sql : t -> string
  val compile : t -> Model.compiled_schema
end
