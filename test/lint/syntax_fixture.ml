(* ^nlint-rv8u: the untyped iterator observes these bindings without leaking scopes. *)
module Root = Eio
module Fiber = Root.Fiber
open Fiber

let outer = fork

module Inner = struct
  module Fiber = Local
  open Other

  let inner = Fiber.fork
end

let after = Fiber.fork

let local =
  let open Local in
  fork

let after_local = fork

let letmodule =
  let module F = Root.Fiber in
  F.fork
