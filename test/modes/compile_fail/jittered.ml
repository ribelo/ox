(* nwake-8qx5: randomness cannot be omitted at construction. *)
let schedule : (unit, int) Ox.Schedule.t =
  Ox.Schedule.jittered (Ox.Schedule.spaced (Ox.Duration.ms 10))
