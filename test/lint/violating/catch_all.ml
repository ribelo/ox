(* ^nlintc-kdcl: catch_all violating evidence. *)
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
