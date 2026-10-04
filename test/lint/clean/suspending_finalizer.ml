(* ^nlintc-kdcl: suspending_finalizer clean evidence. *)
[@@@warning "-32-34-37"]

let synchronous () =
  let x = ref 0 in
  Fun.protect ~finally:(fun () -> x := 1) (fun () -> ())

let protected () =
  Fun.protect
    ~finally:(fun () -> Eio.Cancel.protect (fun () -> Eio.Fiber.yield ()))
    (fun () -> ())

let outer () =
  Eio.Cancel.protect (fun () ->
      Fun.protect ~finally:(fun () -> Eio.Fiber.yield ()) (fun () -> ()))

let release sw = Eio.Switch.on_release sw (fun () -> Eio.Fiber.yield ())

let release_cancellable sw =
  Eio.Switch.on_release_cancellable sw (fun () -> Eio.Fiber.yield ())

let ordinary_body () = Fun.protect ~finally:(fun () -> ()) (fun () -> Eio.Fiber.yield ())

module Fiber = struct
  let yield () = ()
end

let shadowed () = Fun.protect ~finally:(fun () -> Fiber.yield ()) (fun () -> ())
