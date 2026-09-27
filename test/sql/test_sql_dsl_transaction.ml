(* Injected-callback matrix for Eta_sql_dsl.transaction. Disjoint from
   D108/D110/fold suites; register in test/sql/run.ml when granted. *)

open Eta_sql_dsl

exception Begin_boom
exception Body_boom
exception Commit_boom
exception Rollback_boom

type 'a action = Ret of ('a, string) result | Raise of exn

type counts = {
  mutable begins : int;
  mutable bodies : int;
  mutable commits : int;
  mutable rollbacks : int;
  mutable order : string list;
}

let counts () = { begins = 0; bodies = 0; commits = 0; rollbacks = 0; order = [] }
let note t name = t.order <- t.order @ [ name ]

let run_action t name bump action () =
  bump t;
  note t name;
  match action with Ret result -> result | Raise exn -> raise exn

let run ~begin_ ~body ~commit ~rollback =
  let t = counts () in
  let outcome =
    Eta_sql_dsl.transaction
      ~begin_:(fun () ->
        run_action t "begin" (fun t -> t.begins <- t.begins + 1) begin_ ())
      ~commit:(fun () ->
        run_action t "commit" (fun t -> t.commits <- t.commits + 1) commit ())
      ~rollback:(fun () ->
        run_action t "rollback" (fun t -> t.rollbacks <- t.rollbacks + 1) rollback ())
      ()
      (fun () -> run_action t "body" (fun t -> t.bodies <- t.bodies + 1) body ())
  in
  (outcome, t)

let check_counts t ~begins ~bodies ~commits ~rollbacks ~order =
  Alcotest.(check int) "begin count" begins t.begins;
  Alcotest.(check int) "body count" bodies t.bodies;
  Alcotest.(check int) "commit count" commits t.commits;
  Alcotest.(check int) "rollback count" rollbacks t.rollbacks;
  Alcotest.(check (list string)) "callback order" order t.order

let test_commit_success_does_not_rollback () =
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Ret (Ok 7)) ~commit:(Ret (Ok ()))
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Committed 7 -> ()
  | Committed _ -> Alcotest.fail "unexpected committed value"
  | Failed _ -> Alcotest.fail "expected Committed");
  check_counts t ~begins:1 ~bodies:1 ~commits:1 ~rollbacks:0
    ~order:[ "begin"; "body"; "commit" ]

let test_begin_returned_does_not_rollback () =
  let outcome, t =
    run ~begin_:(Ret (Error "begin")) ~body:(Ret (Ok 1)) ~commit:(Ret (Ok ()))
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      { phase = Begin; primary = Returned "begin"; rollback = Rollback_not_attempted } ->
      ()
  | _ -> Alcotest.fail "expected begin returned failure");
  check_counts t ~begins:1 ~bodies:0 ~commits:0 ~rollbacks:0 ~order:[ "begin" ]

let test_begin_raised_does_not_rollback () =
  let outcome, t =
    run ~begin_:(Raise Begin_boom) ~body:(Ret (Ok 1)) ~commit:(Ret (Ok ()))
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      {
        phase = Begin;
        primary = Raised (Begin_boom, _);
        rollback = Rollback_not_attempted;
      } ->
      ()
  | _ -> Alcotest.fail "expected begin raised failure");
  check_counts t ~begins:1 ~bodies:0 ~commits:0 ~rollbacks:0 ~order:[ "begin" ]

let test_body_returned_rolls_back_once () =
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Ret (Error "body")) ~commit:(Ret (Ok ()))
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      { phase = Body; primary = Returned "body"; rollback = Rollback_succeeded } ->
      ()
  | _ -> Alcotest.fail "expected body returned failure");
  check_counts t ~begins:1 ~bodies:1 ~commits:0 ~rollbacks:1
    ~order:[ "begin"; "body"; "rollback" ]

let test_body_raised_rolls_back_once () =
  Printexc.record_backtrace true;
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Raise Body_boom) ~commit:(Ret (Ok ()))
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      { phase = Body; primary = Raised (exn, bt); rollback = Rollback_succeeded } ->
      Alcotest.(check bool) "body exn identity" true (exn = Body_boom);
      Alcotest.(check bool)
        "raw backtrace captured" true
        (Printexc.raw_backtrace_length bt >= 0)
  | _ -> Alcotest.fail "expected body raised failure");
  check_counts t ~begins:1 ~bodies:1 ~commits:0 ~rollbacks:1
    ~order:[ "begin"; "body"; "rollback" ]

let test_commit_returned_rolls_back_once () =
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Ret (Ok 1)) ~commit:(Ret (Error "commit"))
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      { phase = Commit; primary = Returned "commit"; rollback = Rollback_succeeded } ->
      ()
  | _ -> Alcotest.fail "expected commit returned failure");
  check_counts t ~begins:1 ~bodies:1 ~commits:1 ~rollbacks:1
    ~order:[ "begin"; "body"; "commit"; "rollback" ]

let test_commit_raised_rolls_back_once () =
  Printexc.record_backtrace true;
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Ret (Ok 1)) ~commit:(Raise Commit_boom)
      ~rollback:(Ret (Ok ()))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      {
        phase = Commit;
        primary = Raised (Commit_boom, bt);
        rollback = Rollback_succeeded;
      } ->
      Alcotest.(check bool)
        "commit exn identity" true
        (match outcome with
        | Failed { primary = Raised (exn, _); _ } -> exn == Commit_boom
        | _ -> false);
      Alcotest.(check bool)
        "commit backtrace captured" true
        (Printexc.raw_backtrace_length bt >= 0)
  | _ -> Alcotest.fail "expected commit raised failure");
  check_counts t ~begins:1 ~bodies:1 ~commits:1 ~rollbacks:1
    ~order:[ "begin"; "body"; "commit"; "rollback" ]

let test_body_returned_rollback_returned () =
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Ret (Error "body")) ~commit:(Ret (Ok ()))
      ~rollback:(Ret (Error "rollback"))
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      {
        phase = Body;
        primary = Returned "body";
        rollback = Rollback_failed (Returned "rollback");
      } ->
      ()
  | _ -> Alcotest.fail "expected dual returned failures");
  check_counts t ~begins:1 ~bodies:1 ~commits:0 ~rollbacks:1
    ~order:[ "begin"; "body"; "rollback" ]

let test_body_raised_rollback_raised_once () =
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Raise Body_boom) ~commit:(Ret (Ok ()))
      ~rollback:(Raise Rollback_boom)
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      {
        phase = Body;
        primary = Raised (Body_boom, _);
        rollback = Rollback_failed (Raised (Rollback_boom, _));
      } ->
      ()
  | _ -> Alcotest.fail "expected raised primary and rollback");
  check_counts t ~begins:1 ~bodies:1 ~commits:0 ~rollbacks:1
    ~order:[ "begin"; "body"; "rollback" ]

let test_commit_raised_rollback_raised_once () =
  let outcome, t =
    run ~begin_:(Ret (Ok ())) ~body:(Ret (Ok 1)) ~commit:(Raise Commit_boom)
      ~rollback:(Raise Rollback_boom)
  in
  (match outcome with
  | Eta_sql_dsl.Failed
      {
        phase = Commit;
        primary = Raised (Commit_boom, _);
        rollback = Rollback_failed (Raised (Rollback_boom, _));
      } ->
      ()
  | _ -> Alcotest.fail "expected commit raise and rollback raise");
  check_counts t ~begins:1 ~bodies:1 ~commits:1 ~rollbacks:1
    ~order:[ "begin"; "body"; "commit"; "rollback" ]
