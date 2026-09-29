(* nwake-8qx5: all jittering constructors compile with an explicit source. *)
let schedules () =
  let random = Random.State.make [| 17 |] in
  let base = Ox.Schedule.spaced (Ox.Duration.ms 10) in
  let multiplier = Ox.Schedule.jittered ~random base in
  let full = Ox.Schedule.jittered ~random ~kind:Ox.Schedule.Full base in
  let equal = Ox.Schedule.jittered ~random ~kind:Ox.Schedule.Equal base in
  let decorrelated_kind =
    Ox.Schedule.jittered ~random ~kind:Ox.Schedule.Decorrelated base
  in
  let decorrelated =
    Ox.Schedule.decorrelated_jitter ~random ~min:(Ox.Duration.ms 10)
      ~max:(Ox.Duration.ms 100)
  in
  ignore (Ox.Schedule.start multiplier);
  ignore (Ox.Schedule.start full);
  ignore (Ox.Schedule.start equal);
  ignore (Ox.Schedule.start decorrelated_kind);
  ignore (Ox.Schedule.start decorrelated)
