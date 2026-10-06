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
