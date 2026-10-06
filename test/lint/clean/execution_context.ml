(* ^safe-sr6e ^safe-9hbm ^safe-fr73: native work and Eio-context hooks are legal. *)
let native pool =
  Ox_blocking.run ~pool (fun () ->
      Unix.sleepf 0.001;
      6 * 7)

let hooks pool =
  Ox_blocking.run ~pool
    ~on_cancel:(fun () -> Eio.Fiber.yield ())
    ~on_settled:(fun _ -> Eio.Fiber.yield ())
    (fun () -> ())

let dormant pool = Ox_blocking.run ~pool (fun () -> fun () -> Eio.Fiber.yield ())
