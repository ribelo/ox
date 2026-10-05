(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
(* ^nlintd-truth: fork startup differs from synchronous domain joins. *)
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
(* ^nlintd-truth: re-enter a pending prefix through mutual recursion. Its yield
   must survive the cycle, even though the returned functions are not invoked. *)
let rec prefix_first value =
  Eio.Fiber.yield ();
  let next = prefix_second value in
  fun () -> next ()
and prefix_second value =
  let next = prefix_first value in
  fun () -> next ()

let recursive_prefix _ = let ignored = prefix_first () in ignore ignored
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


(* ^nlintd-truth ^nlintd-raises: clean/violating invocation pairs. *)
let protect_wrong callback = try callback () with Invalid_argument _ -> ()
let callback_uncaught _ = protect_wrong (fun () -> raise (Sys_error "read"))

let protect_guarded callback flag =
  try callback () with Sys_error _ when flag -> ()

let callback_guarded _ flag =
  protect_guarded (fun () -> raise (Sys_error "read")) flag

let protect_then_invoke callback =
  (try callback () with Sys_error _ -> ());
  callback ()

let callback_caught_then_uncaught _ =
  protect_then_invoke (fun () -> raise (Sys_error "read"))

let stored_then_called _ =
  let handlers = Hashtbl.create 1 in
  let handler () = assert false in
  Hashtbl.replace handlers "event" handler;
  handler ()

let stored_lookup _ =
  let handlers = Hashtbl.create 1 in
  Hashtbl.replace handlers "event" (fun () -> assert false);
  (Hashtbl.find handlers "event") ()

let fiber_caller_wait sw =
  Eio.Fiber.fork_daemon ~sw (fun () -> assert false);
  Eio.Fiber.yield ()

let fiber_join sw =
  let result = Eio.Fiber.fork_promise ~sw (fun () -> assert false) in
  ignore (Eio.Promise.await_exn result)

let external_callback pool f =
  ignore (Eio.Pool.create 1 f);
  ignore pool
