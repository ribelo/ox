(* ^safe-r5ye: native worker, non-Eio and dormant closures are not violations. *)
let run_native ~pool fn = Ox_blocking.run ~pool fn
let non_eio () = Unix.sleepf 0.01
let worker ~pool () = Eio_main.run (fun _ -> ignore (Ox_blocking.run ~pool (fun () -> Unix.sleepf 0.01)))
let dormant () = Eio_main.run (fun _ -> let wait () = Unix.sleepf 0.01 in ignore wait)
let harmless () = Eio_main.run (fun _ -> ignore (Unix.getpid ()))
module Shadow = struct
  module Unix = struct let sleepf _ = () end
  let run () = Eio_main.run (fun _ -> Unix.sleepf 0.01)
end
let partial_worker () = Eio_main.run (fun _ -> let _partial = Ox_blocking.run ~on_cancel:(fun () -> Unix.sleepf 0.01) (fun () -> ()) in ())
let timer_loop ~clock () = Eio_main.run (fun _ -> let rec tick () = Eio.Time.sleep clock 0.001; tick () in tick ())
let partial_protect () = Eio_main.run (fun _ -> let _partial = Fun.protect (fun () -> Thread.delay 0.01) in ())
let partial_fork () = Eio_main.run (fun _ -> let _partial = Eio.Fiber.fork (fun () -> Unix.sleepf 0.01) in ())
