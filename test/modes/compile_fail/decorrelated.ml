(* nwake-8qx5: standalone decorrelated jitter also requires randomness. *)
let schedule : (unit, Ox.Duration.t) Ox.Schedule.t =
  Ox.Schedule.decorrelated_jitter ~min:(Ox.Duration.ms 10) ~max:(Ox.Duration.ms 100)
