type io = { suspend : unit -> unit } [@@unboxed]
let with_io (f : io @ yielding -> 'a) =
  f { suspend = (fun () -> Eio.Fiber.yield ()) }
let yield (io @ yielding) = io.suspend ()
let critical (f : (unit -> 'a) @ local once unyielding) = f ()
let escapes () = critical (fun () -> with_io (fun io -> yield io))
