(* ^safe-sr6e ^safe-9hbm ^safe-eftp: candidates, not NoEio certificates. *)
module Bridge = Ox_blocking
module Fiber = Eio.Fiber

let callback () = Fiber.yield ()
let direct pool = Bridge.run ~pool callback
let invoke f = f ()
let higher pool = Bridge.run ~pool (fun () -> invoke Fiber.yield)
let pure ?(_unused = ()) () = ()

let ordinary pool opaque =
  Bridge.run ~pool (fun () ->
      opaque ();
      pure ())

let opaque_worker pool callback = Bridge.run ~pool callback
let escape pool opaque = Bridge.run ~pool (fun () -> opaque Fiber.yield)

external foreign : unit -> unit = "unverified_worker_external"

let native pool =
  Bridge.run ~pool (fun () ->
      foreign ();
      ignore (Printexc.to_string Not_found);
      Printf.printf "%d" 1)

let hooks pool = Bridge.run ~pool ~on_cancel:(fun () -> Fiber.yield ()) (fun () -> ())
let returned pool = Bridge.run ~pool (fun () -> fun () -> Fiber.yield ())

module Eio = struct
  module Fiber = struct
    let yield () = ()
  end
end

let shadow pool = Bridge.run ~pool (fun () -> Eio.Fiber.yield ())

module Ox_blocking = struct
  let run ~pool:_ callback = callback ()
end

let unrelated () = Ox_blocking.run ~pool:() (fun () -> Fiber.yield ())
