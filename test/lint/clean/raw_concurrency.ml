(* ^nlintc-kdcl: raw_concurrency clean evidence. *)
[@@@warning "-32-34-37"]

let ordinary () = Eio.Fiber.yield ()

module Eio = struct
  module Fiber = struct
    let fork ~sw:_ f = f ()
  end

  module Switch = struct
    let run f = f ()
  end
end

let shadowed () = Eio.Switch.run (fun () -> Eio.Fiber.fork ~sw:() (fun () -> ()))
