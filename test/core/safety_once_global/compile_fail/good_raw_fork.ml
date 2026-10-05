(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff sw x = Eio.Fiber.fork ~sw (fun () -> ignore x.value)
