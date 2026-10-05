let open_pool ~caps ~sw ~clock =
  Ox_sql.Pool.create ~caps ~sw ~clock ~default_timeout:(Ox.Duration.ms 50)
    (Ox_sql.Sqlite.memory_config ())

let migrate ~caps ~clock pool source = Ox_sql.Migrate.run ~caps ~clock pool source

let migrate_to ~caps ~clock pool source ~target =
  Ox_sql.Migrate.run_to ~caps ~clock pool source ~target

let calendar clock = Eio.Time.now clock
