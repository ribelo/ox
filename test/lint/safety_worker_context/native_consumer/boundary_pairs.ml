let helper ?(_unused = Eio.Fiber.yield ()) () = ()
let optional pool = Ox_blocking.run ~pool (fun () -> helper ())
let dormant () = Ox_blocking.run (fun () -> Eio.Fiber.yield ())

let applied pool =
  let pending = dormant () in
  pending ~pool

let overridden pool = Ox_blocking.run ~pool (fun () -> helper ~_unused:() ())

let matched pool =
  Ox_blocking.run ~pool (fun () ->
    match Some Eio.Fiber.yield with Some f -> f () | None -> ())

let forwarded pool choose =
  Ox_blocking.run ~pool (fun () -> helper ?_unused:(choose ()) ())
