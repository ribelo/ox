(* ^safe-ldtb ^safe-fr73: native typed operation applicability. *)
val run :
  select:'row Ox_sql.Compiled.select ->
  returning:'returned Ox_sql.Compiled.returning ->
  change:Ox_sql.Compiled.change ->
  schema:Ox_sql.Compiled.schema ->
  Ox_sql.Pool.t ->
  (unit, Ox_sql.Pool.error) result
