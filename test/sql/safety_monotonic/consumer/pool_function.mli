val rejected :
  caps:< Ox_caps.Cap.time ; .. > ->
  sw:Eio.Switch.t ->
  clock:(unit -> float) ->
  (Ox_sql.Pool.t, Ox_sql.Pool.error) result
(** Expected installed clock type rejection. *)
