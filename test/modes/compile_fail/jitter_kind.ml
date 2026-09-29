(* nwake-8qx5: jitter kinds have the same required source. *)
let schedule : (unit, int) Ox.Schedule.t =
  Ox.Schedule.jittered ~kind:Ox.Schedule.Full (Ox.Schedule.spaced (Ox.Duration.ms 10))
