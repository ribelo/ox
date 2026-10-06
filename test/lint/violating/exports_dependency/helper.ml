(* ^nlintd-k036 *)
let noop (_ : Eio.Switch.t) = Eio.Fiber.yield ()

(* ^nlintd-k036: exported callers must not count their own unit as delegation. *)
let unknown_body () = ignore (Format.asprintf "%d" 1)
let unknown_raise (_ : Eio.Switch.t) = unknown_body ()
