val open_pool :
  caps:< Ox_caps.Cap.time ; .. > ->
  sw:Eio.Switch.t ->
  clock:Eio.Time.Mono.ty Eio.Time.Mono.t ->
  (Ox_sql.Pool.t, Ox_sql.Pool.error) result
(** ^safe-p9cw ^safe-8peq ^safe-5a9k: installed native clock API control. *)

val migrate :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  clock:Eio.Time.Mono.ty Eio.Time.Mono.t ->
  Ox_sql.Pool.t ->
  Ox_sql.Migrate.Source.t ->
  (Ox_sql.Migrate.run_report, Ox_sql.Migrate.error) result

val migrate_to :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  clock:Eio.Time.Mono.ty Eio.Time.Mono.t ->
  Ox_sql.Pool.t ->
  Ox_sql.Migrate.Source.t ->
  target:Ox_sql.Migrate.Version.t ->
  (Ox_sql.Migrate.run_report, Ox_sql.Migrate.error) result

val calendar : [ `Clock of float ] Eio.Time.clock -> float
