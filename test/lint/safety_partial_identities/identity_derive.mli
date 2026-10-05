open Ocaml_common

type group_kind = Structure | Signature
type group

val group_of_decls :
  source:string ->
  kind:group_kind ->
  recursive:bool ->
  insert_at:int ->
  Parsetree.type_declaration list ->
  group option

val process : filename:string -> source:string -> (string, string) result
