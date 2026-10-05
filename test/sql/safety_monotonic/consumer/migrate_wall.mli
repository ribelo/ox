val rejected :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  Ox_sql.Pool.t ->
  Ox_sql.Migrate.Source.t ->
  clock:[ `Clock of float ] Eio.Time.clock ->
  (Ox_sql.Migrate.run_report, Ox_sql.Migrate.error) result
(** Expected installed clock type rejection. *)
