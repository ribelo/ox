(* ^safe-ctc4 ^safe-tcqo: known indefinite waits, never executed. *)
let direct () = Eio.Cancel.protect (fun () -> Eio.Fiber.await_cancel ())
let alias () =
  let protect = Eio.Cancel.protect and wait = Eio.Fiber.await_cancel in
  protect (fun () -> wait ())
let helper () =
  let wait () = Eio.Fiber.await_cancel () in
  Eio.Switch.run_protected (fun _ -> wait ())
let server socket =
  Eio.Cancel.protect (fun () -> Eio.Net.run_server ~on_error:ignore socket (fun _ _ -> ()))
let mutex lock =
  Eio.Mutex.use_rw ~protect:true lock (fun () -> Eio.Fiber.await_cancel ())
let release sw =
  Eio.Switch.on_release sw (fun () -> Eio.Fiber.await_cancel ())
let substituted () =
  let run first second = first (); second () in
  Eio.Cancel.protect (fun () ->
    run (fun () -> Eio.Fiber.yield ()) (fun () -> Eio.Fiber.await_cancel ()))

let direct_value () = Eio.Cancel.protect Eio.Fiber.await_cancel
