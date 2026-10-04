(* ^nlintc-kdcl: race_deadline clean evidence. *)
[@@@warning "-32-34-37"]

let timeout f = Ox.Timeout.timeout ~clock:(assert false) Ox.Duration.zero f
let successes sw f g = Ox.Concurrent.race ~sw [ f; g ]
let first sw f g = Ox.Concurrent.race_first ~sw [ f; g ]
let any f g = Eio.Fiber.any [ f; g ]

module Concurrent = struct
  let race fs = List.hd fs ()
end

module Time = struct
  let sleep _ _ = ()
end

let unrelated () = Concurrent.race [ (fun () -> Time.sleep () 1.) ]
