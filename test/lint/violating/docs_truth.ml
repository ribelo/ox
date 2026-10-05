(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
(* ^nlintd-truth: fibers and synchronous domain joins are not detached native spawning. *)
let fiber_spawn sw clock = Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 1.)
let domain_join manager clock = Eio.Domain_manager.run manager (fun () -> Eio.Time.sleep clock 1.)
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
(* ^nlintd-truth: neither saturation nor operator continuations erase effects. *)
let ( let* ) value continuation = continuation value
let operator_yield _ = let* () = () in Eio.Fiber.yield ()
let result_operator_yield _ =
  let ( let* ) = Result.bind in
  let* () = Ok () in Eio.Fiber.yield (); Ok ()
let curried _ () = Eio.Fiber.yield ()
let saturated_partial _ = let run = curried () in run ()
let prefixed _ = Eio.Fiber.yield (); fun () -> ()
let prefix_partial _ = let ignored = prefixed () in ignore ignored
let call_local f value = f value
let callback_yield _ = call_local (fun () -> Eio.Fiber.yield ()) ()
let read_optional ?(env = fun _ -> Eio.Fiber.yield (); None) () = env "value"
let optional_default_yield _ = read_optional ()
let functional_compare _ f g = f <> g
let unresolved_operator _ op =
  let ( let* ) = op in
  let* () = () in ()

(* ^nlintd-raises: a tag without its unresolved source remains undecided. *)
let unqualified_input channel _ = input_line channel

