(* ^nlintc-kdcl: suspending_finalizer violating evidence. *)
[@@@warning "-32-34-37"]

let yield () = Fun.protect ~finally:(fun () -> Eio.Fiber.yield ()) (fun () -> ())
let await p = Fun.protect ~finally:(fun () -> Eio.Promise.await p) (fun () -> ())

module F = Eio.Fiber
module P = Fun

let alias () = P.protect ~finally:(fun () -> F.yield ()) (fun () -> ())

let opened () =
  let open Eio.Fiber in
  Fun.protect ~finally:(fun () -> yield ()) (fun () -> ())

let partial () =
  Fun.protect
    ~finally:(fun () ->
      Eio.Cancel.protect (fun () -> Eio.Fiber.yield ());
      Eio.Fiber.yield ())
    (fun () -> ())
