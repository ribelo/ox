(* ^nlintc-kdcl: catch_all clean evidence. *)
[@@@warning "-32-34-37"]

exception Stopped = Eio.Cancel.Cancelled

type raised = { exception_ : exn; backtrace : Printexc.raw_backtrace }

let good f = try f () with Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ()

let opened f =
  let open Eio.Cancel in
  try f () with Cancelled _ as exn -> raise exn | _ -> ()

module C = Eio.Cancel

let aliased f = try f () with C.Cancelled _ as exn -> raise exn | _ -> ()
let rebound f = try f () with Stopped _ as exn -> raise exn | _ -> ()
let propagate f = try f () with exn -> raise exn

let tail ~(caps : < Ox_caps.Cap.stdout ; .. >) f =
  try f ()
  with exn ->
    Ox_caps.Cap_stdlib.print_endline ~caps "ordinary logging";
    raise exn

let specific f = try f () with Not_found -> ()

let exception_arm f =
  match f () with
  | () -> ()
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception _ -> ()

module Fake = struct
  exception Cancelled of exn
end

let unrelated f = try f () with Fake.Cancelled _ as exn -> ignore exn

let backtrace f =
  try f ()
  with exn ->
    let bt = Printexc.get_raw_backtrace () in
    Printexc.raise_with_backtrace exn bt

let cleanup ~(caps : < Ox_caps.Cap.stdout ; .. >) f =
  try f ()
  with Eio.Cancel.Cancelled _ as exn ->
    Ox_caps.Cap_stdlib.print_endline ~caps "release";
    raise exn

let branch f = try f () with exn -> if true then raise exn else ()

let not_a_suspension_rule f =
  try f ()
  with Eio.Cancel.Cancelled _ as exn ->
    Eio.Fiber.yield ();
    raise exn

let reified f =
  try f ()
  with exn ->
    let bt = Printexc.get_raw_backtrace () in
    `Raised (exn, bt)

let tuple f = try f () with exn -> (exn, Printexc.get_raw_backtrace ())

let record f =
  try f () with exn -> { exception_ = exn; backtrace = Printexc.get_raw_backtrace () }

let result f = try f () with exn -> Error exn
let cancellation_data f = try f () with Eio.Cancel.Cancelled _ as exn -> Error exn

(* ^nlintc-du4v ^nlintc-kdcl: delegation follows the actual exception argument. *)
let decision exn =
  match exn with
  | Eio.Cancel.Cancelled _ -> raise exn
  | Invalid_argument _ -> 0
  | _ -> raise exn

let delegated f = try f () with exn -> decision exn

let aliased_helper f =
  let classify = decision in
  try f () with exn -> classify exn

let sibling_helper f = try f () with exn -> Catch_helper.propagate exn

let stored_ref f =
  let raised = ref None in
  (try f () with exn -> raised := Some exn);
  assert (!raised <> None)

let returned_ref f =
  let raised = ref None in
  (try f () with exn -> raised := Some exn);
  !raised

type exception_cell = { mutable raised : exn option }

let stored_field f =
  let cell = { raised = None } in
  (try f () with exn -> cell.raised <- Some exn);
  match cell.raised with Some _ -> true | None -> false

(* ^nlintc-du4v ^nlintc-kdcl: fork-child termination is terminal in libraries. *)
module U = Ox_caps.Cap_unix

let child ~caps f = try f () with _ -> U._exit ~caps 127

let child_tails ~caps f =
  try f ()
  with Eio.Cancel.Cancelled _ as exn ->
    ignore exn;
    let status = 127 in
    if status == 127 then U._exit ~caps status else U._exit ~caps 1

let child_match ~caps f =
  try f ()
  with _ -> ( match true with true -> U._exit ~caps 1 | false -> U._exit ~caps 2)

(* ^nlintc-du4v ^nlintc-kdcl: a presence test is an observable read. *)
let observed_presence ~(caps : < Ox_caps.Cap.stdout ; .. >) f =
  let raised = ref None in
  (try f () with exn -> raised := Some exn);
  Ox_caps.Cap_stdlib.printf ~caps "%b\n" (!raised <> None)
