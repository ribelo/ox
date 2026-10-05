(* ^safe-8peq: function clock cannot satisfy migrate's native clock boundary. *)
let rejected ~caps pool source ~(clock : unit -> float) =
  Ox_sql.Migrate.run ~caps ~clock pool source
