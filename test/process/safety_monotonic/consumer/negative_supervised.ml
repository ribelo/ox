let bad_supervisor ~sw ~spawn (clock : _ Eio.Time.clock) =
  Ox_process.Supervised.start ~sw ~clock ~schedule:Ox.Schedule.forever ~spawn
