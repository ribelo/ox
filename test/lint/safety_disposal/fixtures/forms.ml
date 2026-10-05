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

(* ^safe-s6km: the guard must change the failure outcome, not merely mention it. *)
let guarded_assertion expected r = match r with Error error when error = expected -> () | _ -> Stdlib.failwith "unexpected outcome"
let guarded_recovery expected recover r = match r with Error error when error = expected -> () | _ -> recover ()
let guard_success_only expected observe r = match r with Error error when error = expected -> () | Ok n -> observe n | _ -> ()
let guarded_logging expected r = match r with Error error when error = expected -> () | _ -> prerr_endline "discarded"; ()

(* ^safe-1bc7 ^safe-xls8: actual typed nested wildcards erase stored failures. *)
type result_alias = (int, string) result
type disposal_record = { result : result_alias; number : int }
let tuple_wildcard () = let (_, number) = ((Error "lost" : result_alias), 2) in number
let record_wildcard () = let { result = _; number } = { result = Error "lost"; number = 2 } in number
let unused_wildcard_alias () = let (_ as _lost) = (Error "lost" : result_alias) in ()
let retained_wildcard_alias () = let (_ as retained) = (Error "kept" : result_alias) in retained
let retained_tuple_alias () = let ((_, _) as retained) = ((Error "kept" : result_alias), 2) in retained
let own_tuple_wildcard () = let (_, number) = (Own.Error "not standard", 2) in number
let guarded_direct_logging expected r = match r with Error error when error = expected -> prerr_endline error | _ -> ()
let direct_logging r = match r with Error error -> prerr_endline error | _ -> ()
(* ^safe-1bc7 ^safe-xls8: whole-value alias identity is independent of nesting. *)
let retained_inner_alias () = let (retained as _unused) = (Error "kept" : result_alias) in retained
let retained_outer_alias () = let (_unused as retained) = (Error "kept" : result_alias) in retained
let retained_multi_inner () = let ((retained as _middle) as _outer) = (Error "kept" : result_alias) in retained
let retained_multi_middle () = let ((_inner as retained) as _outer) = (Error "kept" : result_alias) in retained
let retained_multi_outer () = let ((_inner as _middle) as retained) = (Error "kept" : result_alias) in retained
let unused_inner_alias () = let (_inner as _outer) = (Error "lost" : result_alias) in ()
let unused_multi_alias () = let ((_inner as _middle) as _outer) = (Error "lost" : result_alias) in ()
let shadowed_inner_alias () = let (retained as _unused) = (Error "lost" : result_alias) in let retained = Ok 2 in retained
let shadowed_outer_alias () = let (_unused as retained) = (Error "lost" : result_alias) in let retained = Ok 2 in retained
let discarded_inner_alias () = let (retained as _unused) = (Error "lost" : result_alias) in ignore retained
let nested_tuple_alias () = let ((_, number) as _unused) = ((Error "lost" : result_alias), 2) in number
let retained_inner_tuple () = let (retained as _unused) = ((Error "kept" : result_alias), 2) in retained
let retained_multi_tuple () = let (((_, _) as retained) as _unused) = ((Error "kept" : result_alias), 2) in retained
let nested_record_alias () = let ({ result = _; number } as _unused) = { result = Error "lost"; number = 2 } in number
let own_unused_alias () = let (_inner as _outer) = Own.Error "not standard" in ()
