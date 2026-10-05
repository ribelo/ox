(* ^safe-8peq: wall clock cannot satisfy run_to's native clock boundary. *)
let rejected ~caps pool source ~(clock : [ `Clock of float ] Eio.Time.clock) =
  Ox_sql.Migrate.run_to ~caps ~clock pool source
    ~target:(Ox_sql.Migrate.Version.from_int64_unchecked 1L)
