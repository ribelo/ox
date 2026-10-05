(* ^safe-8peq: wall clock cannot satisfy migrate's native clock boundary. *)
let rejected ~caps pool source ~(clock : [ `Clock of float ] Eio.Time.clock) =
  Ox_sql.Migrate.run ~caps ~clock pool source
