let elapsed clock =
  let started = Eio.Time.now clock in
  Eio.Time.now clock -. started

let expired clock =
  let due = Eio.Time.now clock +. 1. in
  Eio.Time.now clock >= due

let sleep clock = Eio.Time.sleep clock (Eio.Time.now clock)

let timeout clock =
  Eio.Time.with_timeout clock (Unix.gettimeofday ()) (fun () -> Ok ())

let caps_elapsed ~caps =
  let started = Ox_caps.Cap_unix.gettimeofday ~caps () in
  Ox_caps.Cap_unix.gettimeofday ~caps () -. started
