(* ^nlintc-kdcl: raw_concurrency violating evidence. *)
[@@@warning "-32-34-37"]

let fork sw = Eio.Fiber.fork ~sw (fun () -> ())
let both () = Eio.Fiber.both (fun () -> ()) (fun () -> ())
let any () = Eio.Fiber.any [ (fun () -> ()) ]
let switch () = Eio.Switch.run (fun _ -> ())
let release sw = Eio.Switch.on_release sw (fun () -> ())
let mutex () = Eio.Mutex.create ()
let map () = Eio.Fiber.List.map Fun.id []

module F = Eio.Fiber

let alias sw = F.fork ~sw (fun () -> ())
