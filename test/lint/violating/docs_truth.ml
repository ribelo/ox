(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
let alias = Docs_dependency.noop
let forward sw = alias sw
let no_check sw = Eio.Switch.check sw
let wrong_raise _ = failwith "bad"
let unattested _ = ()
let callback _ f = f ()
let success_only ~caps sw filename = let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in Eio.Switch.check sw; close_out resource
let late_hook ~caps sw filename = let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in Eio.Switch.check sw; Eio.Switch.on_release sw (fun () -> close_out resource)
let irrelevant_hook ~caps sw filename = let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in Eio.Switch.on_release sw (fun () -> ignore resource); Eio.Switch.check sw
let conditional_hook ~caps sw filename flag = let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in if flag then Eio.Switch.on_release sw (fun () -> close_out resource); Eio.Switch.check sw
let cancellable_finalizer ~caps sw filename = let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in Fun.protect ~finally:(fun () -> Eio.Fiber.yield (); close_out resource) (fun () -> Eio.Switch.check sw)
let partial_catch _ =
  try invalid_arg "bad" with Invalid_argument msg when msg = "other" -> ()
let locking_only _ f = f ()
let masked_added_check sw = Eio.Cancel.protect (fun () -> Eio.Switch.check sw)
let protected_cancellation _ = Eio.Cancel.protect (fun () -> raise (Eio.Cancel.Cancelled (Failure "explicit")))
let swallowed_cancel ~caps sw filename = let resource = Ox_caps.Cap_stdlib.open_out ~caps filename in ignore resource; try Eio.Switch.check sw with Eio.Cancel.Cancelled _ -> ()
