(* ^safe-8peq: function clock cannot satisfy run_to's native clock boundary. *)
let rejected ~caps pool source ~(clock : unit -> float) =
  Ox_sql.Migrate.run_to ~caps ~clock pool source
    ~target:(Ox_sql.Migrate.Version.from_int64_unchecked 1L)
