(* ^safe-8peq: function clock cannot satisfy pool's native clock boundary. *)
let rejected ~caps ~sw ~(clock : unit -> float) =
  Ox_sql.Pool.create ~caps ~sw ~clock (Ox_sql.Sqlite.memory_config ())
