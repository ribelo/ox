(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)
[@@@warning "-32-34-37"]

exception Stopped = Eio.Cancel.Cancelled

let swallowed f = try f () with Eio.Cancel.Cancelled _ as exn -> ignore exn

let cleanup_then_raise f =
  try f ()
  with Eio.Cancel.Cancelled _ as exn ->
    print_endline "release";
    raise exn

let rebound f = try f () with Stopped _ as exn -> ignore exn
let wildcard f = try f () with _ -> ()
let bound f = try f () with exn -> ignore exn
let underscore f = try f () with _exn -> ()
let exception_arm f = match f () with () -> () | exception _ -> ()

let guarded f =
  try f () with Eio.Cancel.Cancelled _ as exn when false -> raise exn | _ -> ()

let constructed_but_dropped f =
  try f ()
  with exn ->
    ignore (Error exn);
    ()

let different_exception f =
  try f ()
  with exn ->
    ignore exn;
    raise Exit

(* ^nlintc-du4v ^nlintc-kdcl: logging, opaque/deferred calls and unobserved stores. *)
let logs exn = ignore exn
let logging_helper f = try f () with exn -> logs exn
let opaque_helper classify f = try f () with exn -> classify exn
let defer exn = fun () -> raise exn
let deferred_helper f = try f () with exn -> defer exn

let unobserved_ref f =
  let raised = ref None in
  try f () with exn -> raised := Some exn

let deferred_reader f =
  let raised = ref None in
  (try f () with exn -> raised := Some exn);
  fun () -> !raised

let overwritten_ref f =
  let raised = ref None in
  (try f () with exn -> raised := Some exn);
  raised := None;
  !raised

let discarded_read f =
  let raised = ref None in
  (try f () with exn -> raised := Some exn);
  ignore !raised;
  ()

type exception_cell = { mutable raised : exn option }
let unobserved_field f =
  let cell = { raised = None } in
  try f () with exn -> cell.raised <- Some exn

(* ^nlintc-du4v ^nlintc-kdcl: an exit on only one result cannot license the other. *)
let child_branch ~caps terminate f =
  try f () with _ -> if terminate then Ox_caps.Cap_unix._exit ~caps 127 else ()

let child_discarded ~caps f =
  try f () with _ -> ignore (fun () -> Ox_caps.Cap_unix._exit ~caps 127)

let child_rhs ~caps f =
  try f () with _ -> let _ = Ox_caps.Cap_unix._exit ~caps 127 in ()
