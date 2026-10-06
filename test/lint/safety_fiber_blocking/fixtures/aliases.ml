(* ^safe-9ved ^safe-r5ye: local and module aliases preserve compiler identity. *)
module U = Unix
let wait = U.sleepf
let helper delay = wait delay
let run () = Eio_main.run (fun _ -> helper 0.01)
let integers () = Eio_main.run (fun _ -> Unix.sleep 1)
let threads () = Eio_main.run (fun _ -> Thread.delay 0.01)
let transfer () = Eio_main.run (fun _ -> Eio.Fiber.both (fun () -> wait 0.01) (fun () -> ()))
let optional ?(wait = let () = Unix.sleepf 0.01 in fun () -> ()) () = wait ()
let defaults () = Eio_main.run (fun _ -> optional ())
let protected () = Eio_main.run (fun _ -> Fun.protect ~finally:(fun () -> Unix.sleepf 0.01) (fun () -> ()))
let option_callback () = Eio_main.run (fun _ -> Option.iter (fun () -> Thread.delay 0.01) (Some ()))
let forwarded () = Ox_test.run (fun _ _ -> Unix.sleepf 0.01)
let combined () = Eio_main.run (fun _ -> ignore (Eio.Fiber.first ~combine:(fun () () -> Unix.sleepf 0.01) (fun () -> ()) (fun () -> ())))
