(* ^safe-vj9b: finite cleanup, ready settlement, and unused closures. *)
let ready () =
  let settled = Eio.Promise.create_resolved () in
  Eio.Cancel.protect (fun () -> Eio.Promise.await settled)

let finite clock = Eio.Cancel.protect (fun () -> Eio.Time.sleep clock 0.001)

let local () =
  let teardown () = Eio.Fiber.yield () in
  Eio.Cancel.protect teardown

let dormant () = Eio.Cancel.protect (fun () -> fun () -> Eio.Fiber.await_cancel ())

module Shadow = struct
  let protect f = f ()
  let await_cancel () = ()
end

let shadow () = Shadow.protect (fun () -> Shadow.await_cancel ())
let unmasked lock = Eio.Mutex.use_rw ~protect:false lock (fun () -> Eio.Fiber.yield ())

let partial () =
  let never _x _y = Eio.Fiber.await_cancel () in
  Eio.Cancel.protect (fun () -> never ())

let partial_server socket =
  let _later = Eio.Cancel.protect (fun () -> Eio.Net.run_server socket (fun _ _ -> ())) in
  ()

let opaque_cleanup f = Eio.Cancel.protect f
