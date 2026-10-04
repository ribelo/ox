(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
let alias = Docs_dependency.noop
let forward sw = alias sw

let dormant _ =
  let ignored () = Eio.Fiber.yield () in
  ignore ignored

let caught _ = try invalid_arg "bad" with Invalid_argument _ -> ()
let raises sw = if sw == sw then invalid_arg "bad"
let protected _ = Eio.Cancel.protect (fun () -> Eio.Fiber.yield ())

let hook ~caps sw filename =
  let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in
  Eio.Switch.on_release sw (fun () -> close_out resource);
  Eio.Switch.check sw

let bracket ~caps sw filename =
  let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in
  Fun.protect ~finally:(fun () -> close_out resource) (fun () -> Eio.Switch.check sw)

let masked_check sw = Eio.Cancel.protect (fun () -> Eio.Switch.check sw)
let protected_raise _ = Eio.Cancel.protect (fun () -> failwith "explicit")

let match_caught _ =
  match invalid_arg "bad" with () -> () | exception Invalid_argument _ -> ()

let release_failure () = invalid_arg "release"
let release_raises sw = Eio.Switch.on_release sw release_failure
let finalizer_failure () = failwith "cleanup"
let finalizer_raises _ = Fun.protect ~finally:finalizer_failure (fun () -> ())

(* ^nlintd-truth *)
let primitives _ n =
  let cell = Atomic.make (n + 1) in
  Atomic.get cell - 1

let buffered_publish stream = Eio.Stream.add stream ()
