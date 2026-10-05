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

(* ^nlintd-truth: background native execution is not caller suspension. *)
let thread_spawn clock = ignore (Thread.create (fun () -> Eio.Time.sleep clock 1.) ())
let domain_spawn clock = ignore (Domain.spawn (fun () -> Eio.Time.sleep clock 1.))
let background clock = Eio.Time.sleep clock 1.
let named_thread_spawn clock = ignore (Thread.create background clock)

(* ^nlintd-truth: visible operators, higher-order locals and default readers. *)
let ( let* ) value continuation = continuation value

let visible_operator _ =
  let* () = () in
  ()

let result_operator _ =
  let open Result.Syntax in
  let* () = Ok () in
  Ok ()

let call_local f value = f value
let local_callback _ = call_local (fun () -> ()) ()
let discard_callback f = ignore f
let ignored_callback _ = discard_callback (fun () -> Eio.Fiber.yield ())
let curried _ () = Eio.Fiber.yield ()

let deferred_partial _ =
  let deferred = curried () in
  ignore deferred

let sync_reader key = if String.trim key <> "" then Some key else None
let read_optional ?(env = sync_reader) () = env "value"
let optional_default _ = read_optional ()

let scalar_leaves _ input =
  let n = Option.value (int_of_string_opt (String.trim input)) ~default:0 in
  ignore (Filename.concat input (string_of_int n));
  n > 0

(* ^nlintd-truth: nema db.ml maps a recursive case function partially applied
   to its fixed environment; constructing that callback executes no case. *)
type nested = Leaf | Branch of nested list

let rec map_nested callback = function
  | Leaf -> callback ()
  | Branch children -> List.iter (map_nested callback) children

let recursive_partial _ =
  let deferred = map_nested (fun () -> Eio.Fiber.yield ()) in
  ignore deferred

let recursive_quiet _ = map_nested (fun () -> ()) (Branch [ Leaf ])
let recursive_active _ = map_nested (fun () -> Eio.Fiber.yield ()) (Branch [ Leaf ])

(* ^nlintd-raises: named external raise assertions stay local to this contract. *)
let delegated_input channel _ = input_line channel
