(* ^safe-sr6e ^safe-eftp: suspension belongs on the Eio caller side, not the worker. *)
let broken pool = Ox_blocking.run ~pool (fun () -> Eio.Fiber.yield ())

module Bridge = Ox_blocking
module Fiber = Eio.Fiber

let result pool =
  let callback () =
    Fiber.yield ();
    Ok ()
  in
  Bridge.run_result ~pool callback

(* ^safe-9ved ^safe-r5ye: finite exact native wait identities. *)
let fractional () = Eio_main.run (fun _ -> Unix.sleepf 0.001)
let integer () = Eio_main.run (fun _ -> Unix.sleep 1)
let thread () = Eio_main.run (fun _ -> Thread.delay 0.001)
let counting semaphore () = Eio_main.run (fun _ -> Semaphore.Counting.acquire semaphore)
