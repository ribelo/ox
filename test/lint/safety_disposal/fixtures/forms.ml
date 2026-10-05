(* ^safe-1bc7: binding identity, not spelling. *)
let unused () =
  let _named = (Ok 1 : (int, string) result) in
  ()

let shadowed () =
  let _r = (Ok 1 : (int, string) result) in
  let _r = 2 in
  ignore _r

let erased r = match r with Ok _ -> () | Error _ -> ()

let logged r =
  match r with
  | Ok _ -> ()
  | Error e ->
      prerr_endline e;
      ()

let option r = Result.to_option r
let iterator r = Result.iter (fun _ -> ()) r
let direct () = ignore (Ok 1 : (int, string) result)

let aliases () =
  let discard = Stdlib.ignore in
  discard (Ok 1 : (int, string) result)

let constant_alias r =
  let fallback = () in
  match r with Ok _ -> () | Error _ -> fallback

let piped (r : (int, string) result) = r |> Stdlib.ignore
let applied (r : (int, string) result) = Stdlib.ignore @@ r

let destructured () =
  let r, n = ((Ok 1 : (int, string) result), 2) in
  n

let recover r = match r with Ok n -> n | Error e -> String.length e
let mapped r = match r with Ok n -> Ok n | Error e -> Error (`Named e)

module Own = struct
  type ('a, 'e) result = Error of 'e | Ok of 'a
end

let homonym r = match r with Own.Ok _ -> () | Own.Error _ -> ()

let propagated () =
  let r = (Ok 1 : (int, string) result) in
  r

let used () =
  let r = (Ok 1 : (int, string) result) in
  match r with Ok n -> n | Error e -> String.length e

(* ^safe-s6km: status, named domain mapping, retained results and real recovery. *)
let classified r = match r with Ok _ -> true | Error _ -> false

let status r =
  match r with
  | Ok _ -> 0
  | Error e ->
      prerr_endline e;
      2

let observed r =
  (match r with Ok _ -> () | Error _ -> ());
  r

let discriminated r =
  match r with Ok n -> Some n | Error `Empty -> None | Error `Timeout -> None

let close_recovery close r =
  match r with
  | Ok _ -> ()
  | Error _ ->
      close ();
      ()

let computed_health r = match r with Ok n -> n > 0 | Error _ -> false

let expected_error r = match r with Error _ -> () | _ -> Alcotest.fail "composite cause projected as typed error"
let unexpected_error r = match r with Ok _ -> () | Error _ -> Alcotest.fail "unexpected failure"

(* ^safe-s6km: expected-error assertions resolve a real terminal standard value. *)
let expected_error_stdlib r = match r with Error _ -> () | _ -> Stdlib.failwith "decode raised an expected error"

(* ^safe-s6km: payload observation is tied to the actual error binder. *)
let checked_payload expected r = match r with Error error when error = expected -> () | _ -> ()

(* ^safe-s6km: lookalikes and constant/unrelated guards do not handle failures. *)
let shadowed_terminal r =
  let module Stdlib = struct let failwith _ = () end in
  match r with Error _ -> () | _ -> Stdlib.failwith "not terminal"

let unchecked_payload r = match r with Error _ when true -> () | _ -> ()

let unrelated_guard error expected r = match r with Error _ when error = expected -> () | _ -> ()

let shadowed_comparison expected r =
  let ( = ) _ _ = true in
  match r with Error error when error = expected -> () | _ -> ()

let expected_error_predef r = match r with Error _ -> () | _ -> failwith "expected error"
let expected_error_invalid_arg r = match r with Error _ -> () | _ -> Stdlib.invalid_arg "expected error"
let expected_error_raise r = match r with Error _ -> () | _ -> Stdlib.raise Exit
let expected_error_raise_notrace r = match r with Error _ -> () | _ -> Stdlib.raise_notrace Exit
