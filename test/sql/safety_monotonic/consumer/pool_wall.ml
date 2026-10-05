(* ^safe-8peq: wall clock cannot satisfy pool's native clock boundary. *)
let rejected ~caps ~sw ~(clock : [ `Clock of float ] Eio.Time.clock) =
  Ox_sql.Pool.create ~caps ~sw ~clock (Ox_sql.Sqlite.memory_config ())
