(* Row 45: supervised scopes with application errors, Concurrent over Eio, Retry policy,
   Schedule vocabulary. Every case cites its story IDs (nsup IDs). *)
(* ^safe-1bc7 ^safe-xls8: Assert scripted outcomes instead of discarding results;
   lifetime, cancellation and failure observations remain independently checked. *)
open Ox

let check_bool = Alcotest.(check bool)
let check_int = Alcotest.(check int)

exception Boom of string

(* Live-fiber census: every fiber that starts counts itself in and out. *)
let live = ref 0

let counted body =
  incr live;
  Fun.protect body ~finally:(fun () -> decr live)

let blocked () = counted (fun () -> Eio.Fiber.await_cancel ())

let yields n =
  for _ = 1 to n do
    Eio.Fiber.yield ()
  done

let census label =
  check_int (label ^ ": every fork awaited (fiber census)") 0 !live;
  live := 0

let with_outer f =
  Eio_main.run (fun _ ->
      live := 0;
      Eio.Switch.run f)

(* ---- nsup-xkke nsup-a4bf: a typed error ends the scope --------------------------------- *)

let error_ends_scope () =
  with_outer (fun sw ->
      (* a fork's Error cancels and awaits the other forks *)
      let result =
        Scope.supervised_error ~sw (fun scope ->
            ignore (Scope.fork_error scope blocked);
            Scope.fork scope (fun () -> blocked ());
            ignore
              (Scope.fork_error scope (fun () ->
                   counted (fun () ->
                       yields 1;
                       Error "boom")));
            Ok "body")
      in
      check_bool "fork Error is the scope's result" true (result = Error "boom");
      census "fork error";
      (* the first error wins *)
      let result =
        Scope.supervised_error ~sw (fun scope ->
            ignore
              (Scope.fork_error scope (fun () ->
                   yields 2;
                   Error "late"));
            ignore
              (Scope.fork_error scope (fun () ->
                   yields 1;
                   Error "early"));
            Ok ())
      in
      check_bool "first error wins" true (result = Error "early");
      (* nsup-a4bf: the body's own Error ends the scope the same way *)
      let result =
        Scope.supervised_error ~sw (fun scope ->
            ignore (Scope.fork_error scope blocked);
            Scope.fork scope (fun () -> blocked ());
            Eio.Fiber.yield ();
            Error "body")
      in
      check_bool "body Error ends the scope" true (result = Error "body");
      census "body error";
      (* success: forks are waited for and the body's value returned *)
      let done_forks = ref 0 in
      let result =
        Scope.supervised_error ~sw (fun scope ->
            for _ = 1 to 3 do
              ignore
                (Scope.fork_error scope (fun () ->
                     yields 2;
                     incr done_forks;
                     Ok ()))
            done;
            Ok "value")
      in
      check_bool "success" true (result = Ok "value");
      check_int "a returning body still waits for its forks" 3 !done_forks;
      (* an Error raised by Scope.run sees a plain typed failure *)
      match
        Scope.run (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                ignore (Scope.fork_error scope blocked);
                ignore
                  (Scope.fork_error scope (fun () ->
                       Eio.Fiber.yield ();
                       Error "typed"));
                Ok ()))
      with
      | Exit.Failure (Cause.Fail "typed") -> ()
      | _ -> Alcotest.fail "Scope.run must see Fail, not an interruption")

(* ---- nsup-hm4o: plain forks -------------------------------------------------------------- *)

let plain_forks () =
  with_outer (fun sw ->
      let ran = ref 0 and daemon_cleaned = ref false in
      let result =
        Scope.supervised_error ~sw (fun scope ->
            Scope.fork scope (fun () ->
                yields 2;
                incr ran);
            Scope.fork_daemon scope (fun () ->
                Fun.protect
                  (fun () -> Eio.Fiber.await_cancel ())
                  ~finally:(fun () -> daemon_cleaned := true));
            Ok "ok")
      in
      check_bool "result" true (result = Ok "ok");
      check_int "plain fork ran to completion before the scope returned" 1 !ran;
      check_bool "daemon cancelled at scope end" true !daemon_cleaned;
      (* a plain fork's exception ends the scope *)
      let boom = Boom "plain" in
      match
        Scope.supervised_error ~sw (fun scope ->
            ignore (Scope.fork_error scope blocked);
            Scope.fork scope (fun () ->
                Eio.Fiber.yield ();
                raise boom);
            Ok ())
      with
      | exception ex -> check_bool "same exception" true (ex == boom)
      | _ -> Alcotest.fail "plain fork exception was swallowed")

(* ---- nsup-xzl3: await ------------------------------------------------------------------- *)

let await_handle () =
  with_outer (fun sw ->
      let result =
        Scope.supervised_error ~sw (fun scope ->
            let a =
              Scope.fork_error scope (fun () ->
                  yields 2;
                  Ok 20)
            in
            let b =
              Scope.fork_error scope (fun () ->
                  yields 1;
                  Ok 22)
            in
            match (Scope.await a, Scope.await b) with
            | Ok a, Ok b -> Ok (a + b)
            | _ -> Error "unexpected")
      in
      check_bool "typed successes joined and used" true (result = Ok 42);
      let after_error = ref false in
      let result =
        Scope.supervised_error ~sw (fun scope ->
            let f =
              Scope.fork_error scope (fun () ->
                  yields 1;
                  Error "nope")
            in
            ((match Scope.await f with
            | Error _ | Ok _ -> ()
            | exception Eio.Cancel.Cancelled _ -> ())
            [@ox.allow
              "ox-discarded-result: safe-xls8 safe-pufa; observe scope-driven \
               cancellation, not the join reply; outer assertions require Error nope and \
               that the joiner never runs on"]);
            Eio.Fiber.yield ();
            after_error := true;
            Ok ())
      in
      check_bool "the scope ends with the awaited fork's error" true
        (result = Error "nope");
      check_bool "the joiner did not run on after the scope ended" false !after_error)

(* ---- nsup-1lzt: exceptions ------------------------------------------------------------- *)

let exceptions () =
  with_outer (fun sw ->
      let boom = Boom "fork" in
      (match
         Scope.supervised_error ~sw (fun scope ->
             ignore (Scope.fork_error scope blocked);
             ignore
               (Scope.fork_error scope (fun () ->
                    Eio.Fiber.yield ();
                    raise boom));
             Ok ())
       with
      | exception ex -> check_bool "fork exception raised unchanged" true (ex == boom)
      | _ -> Alcotest.fail "fork exception swallowed");
      census "fork exception";
      let boom = Boom "body" in
      (match
         Scope.supervised_error ~sw (fun scope ->
             ignore (Scope.fork_error scope blocked);
             Eio.Fiber.yield ();
             raise boom)
       with
      | exception ex -> check_bool "body exception raised unchanged" true (ex == boom)
      | _ -> Alcotest.fail "body exception swallowed");
      census "body exception";
      (* Scope.run sees the defect alone: the losers' interruption is suppressed onto it *)
      let boom = Boom "cause" in
      (match
         Scope.run (fun sw ->
             Scope.supervised_error ~sw (fun scope ->
                 ignore (Scope.fork_error scope blocked);
                 Scope.fork scope (fun () -> blocked ());
                 ignore
                   (Scope.fork_error scope (fun () ->
                        Eio.Fiber.yield ();
                        raise boom));
                 Ok ()))
       with
      | Exit.Failure (Cause.Die (ex, _)) when ex == boom -> ()
      | Exit.Failure cause ->
          Alcotest.failf "expected Die alone: %a" (Cause.pp Format.pp_print_string) cause
      | Exit.Success _ -> Alcotest.fail "expected failure");
      census "cause";
      (* an exception and a typed error in the same scope: the exception is what you get.
         The raising fork is protected so it still raises after the Error cancelled it. *)
      let boom = Boom "beats typed" in
      match
        Scope.supervised_error ~sw (fun scope ->
            ignore
              (Scope.fork_error scope (fun () ->
                   Eio.Fiber.yield ();
                   Error "typed"));
            ignore
              (Scope.fork_error scope (fun () ->
                   Eio.Cancel.protect (fun () ->
                       Eio.Fiber.yield ();
                       Eio.Fiber.yield ();
                       raise boom)));
            Ok ())
      with
      | exception ex -> check_bool "exception wins over typed error" true (ex == boom)
      | Ok _ | Error _ -> Alcotest.fail "exception lost to a typed error")

(* ---- nsup-5j80: cancellation ---------------------------------------------------------- *)

(* Run [body] inside a cancellation context that is cancelled with a private identity once
   [body] has had a chance to start. *)
let cancelled_caller body =
  let id = Interrupt_id.create () in
  let outcome =
    Scope.run (fun sw' ->
        Eio.Cancel.sub (fun ctx ->
            Eio.Fiber.fork ~sw:sw' (fun () ->
                yields 3;
                Eio.Cancel.cancel ctx (Interrupt_id.stop id));
            body sw'))
  in
  (id, outcome)

let is_interrupt id = function
  | Exit.Failure (Cause.Interrupt (Some seen)) -> Interrupt_id.equal id seen
  | _ -> false

let cancellation () =
  with_outer (fun sw ->
      let id, outcome =
        cancelled_caller (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                ignore (Scope.fork_error scope blocked);
                Scope.fork scope (fun () -> blocked ());
                Eio.Fiber.await_cancel ()))
      in
      check_bool "caller cancellation propagates with its identity" true
        (is_interrupt id outcome);
      census "cancelled";
      (* a typed error that lands after the caller was cancelled stays a cancellation *)
      let id, outcome =
        cancelled_caller (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                ignore
                  (Scope.fork_error scope (fun () ->
                       Eio.Cancel.protect (fun () ->
                           yields 6;
                           Error "late")));
                ignore (Scope.fork_error scope blocked);
                Eio.Fiber.await_cancel ()))
      in
      check_bool "never turned into a typed error" true (is_interrupt id outcome);
      census "cancelled with late error")

(* ---- nsup-hd24 nsup-q444: the combinators run in the caller's cancellation context ------ *)

let combinators_cancel () =
  with_outer (fun _ ->
      let check name start =
        let id, outcome = cancelled_caller (fun sw -> start sw) in
        check_bool
          (name ^ ": caller cancellation propagates with its identity")
          true (is_interrupt id outcome);
        census name
      in
      let forever () : (unit, string) result = blocked () in
      check "par" (fun sw ->
          Concurrent.par ~sw forever forever |> Stdlib.Result.map ignore);
      check "both" (fun sw -> Concurrent.both ~sw forever forever);
      check "all" (fun sw ->
          Concurrent.all ~sw [ forever; forever ] |> Stdlib.Result.map ignore);
      check "race" (fun sw ->
          Concurrent.race ~sw [ forever; forever ]
          |> Stdlib.Result.map_error (fun _ -> "race"));
      check "race_first" (fun sw -> Concurrent.race_first ~sw [ forever; forever ]);
      check "for_each" (fun sw ->
          Concurrent.for_each ~sw ~concurrency:2 [ 1; 2; 3 ] (fun _ -> forever ())
          |> Stdlib.Result.map ignore);
      check "with_background" (fun sw -> Concurrent.with_background ~sw forever forever))

(* nsup-hd24: for_each bounds concurrency, keeps order, stops at the first error *)
let for_each () =
  with_outer (fun sw ->
      let current = ref 0 and peak = ref 0 in
      let f x =
        incr current;
        peak := max !peak !current;
        yields 2;
        decr current;
        Ok (x * 10)
      in
      let result = Concurrent.for_each ~sw ~concurrency:2 [ 1; 2; 3; 4; 5; 6 ] f in
      check_bool "results in input order" true (result = Ok [ 10; 20; 30; 40; 50; 60 ]);
      check_int "at most [concurrency] at once" 2 !peak;
      check_bool "empty" true (Concurrent.for_each ~sw ~concurrency:3 [] f = Ok []);
      let started = ref [] in
      let result =
        Concurrent.for_each ~sw ~concurrency:2 [ 1; 2; 3; 4; 5; 6 ] (fun x ->
            started := x :: !started;
            yields 1;
            if x = 3 then Error "three" else Ok x)
      in
      check_bool "first error" true (result = Error "three");
      check_bool "later items never started" false (List.mem 6 !started);
      match Concurrent.for_each ~sw ~concurrency:0 [ 1 ] f with
      | exception Invalid_argument _ -> ()
      | _ -> Alcotest.fail "concurrency 0 accepted")

(* ---- nsup-i1zm: the law, over every outcome pattern and every settling order ----------- *)

type outcome = Value of int | Typed of string | Raise of exn | Block

let show = function
  | Value v -> Printf.sprintf "Value %d" v
  | Typed e -> "Typed " ^ e
  | Raise (Boom m) -> "Raise " ^ m
  | Raise _ -> "Raise"
  | Block -> "Block"

(* [delay] yields, then the outcome: distinct delays make the settling order exact. *)
let branch ~delay outcome () : (int, string) result =
  counted (fun () ->
      yields delay;
      match outcome with
      | Value v -> Ok v
      | Typed e -> Error e
      | Raise ex -> raise ex
      | Block -> Eio.Fiber.await_cancel ())

type 'a observed = Returned of 'a | Raised of exn

let observe thunk = try Returned (thunk ()) with ex -> Raised ex

let rec permutations = function
  | [] -> [ [] ]
  | xs ->
      List.concat_map
        (fun x ->
          List.map (fun rest -> x :: rest) (permutations (List.filter (( <> ) x) xs)))
        xs

let outcome_space n =
  let mk i kind =
    match kind with
    | 0 -> Value (100 + i)
    | 1 -> Typed (Printf.sprintf "e%d" i)
    | 2 -> Raise (Boom (Printf.sprintf "x%d" i))
    | _ -> Block
  in
  let rec build i =
    if i = n then [ [] ]
    else
      List.concat_map
        (fun rest -> List.init 4 (fun kind -> mk i kind :: rest))
        (build (i + 1))
  in
  build 0

let failing = function Typed _ | Raise _ -> true | Value _ | Block -> false

(* [expected] for the group combinators: the failing branch that settles first, else the
   values in order, else the case would never settle (skipped). *)
let group_expected cells =
  let failures = List.filter (fun (_, o) -> failing o) cells in
  match List.sort (fun (a, _) (b, _) -> compare a b) failures with
  | (_, Typed e) :: _ -> Some (Returned (Error e))
  | (_, Raise ex) :: _ -> Some (Raised ex)
  | _ :: _ -> assert false
  | [] ->
      if List.exists (fun (_, o) -> o = Block) cells then None
      else
        Some
          (Returned (Ok (List.map (function _, Value v -> v | _ -> assert false) cells)))

let same_observation label expected actual =
  let ok =
    match (expected, actual) with
    | Returned a, Returned b -> a = b
    | Raised a, Raised b -> a == b
    | _ -> false
  in
  if not ok then Alcotest.failf "law broken: %s" label

let law_group () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let cases = ref 0 in
          let combinators =
            [
              ( "par",
                2,
                fun tasks ->
                  match tasks with
                  | [ f; g ] ->
                      Concurrent.par ~sw f g |> Stdlib.Result.map (fun (a, b) -> [ a; b ])
                  | _ -> assert false );
              ( "both",
                2,
                fun tasks ->
                  match tasks with
                  | [ f; g ] ->
                      let unit_ f () = Stdlib.Result.map ignore (f ()) in
                      Concurrent.both ~sw (unit_ f) (unit_ g)
                      |> Stdlib.Result.map (fun () -> [])
                  | _ -> assert false );
              ("all", 3, fun tasks -> Concurrent.all ~sw tasks);
              ("all2", 2, fun tasks -> Concurrent.all ~sw tasks);
              ( "for_each",
                3,
                fun tasks -> Concurrent.for_each ~sw ~concurrency:3 tasks (fun f -> f ())
              );
            ]
          in
          List.iter
            (fun (name, n, run) ->
              List.iter
                (fun outcomes ->
                  List.iter
                    (fun delays ->
                      let cells = List.combine delays outcomes in
                      match group_expected cells with
                      | None -> ()
                      | Some expected ->
                          incr cases;
                          live := 0;
                          let tasks =
                            List.map (fun (delay, o) -> branch ~delay o) cells
                          in
                          let actual = observe (fun () -> run tasks) in
                          let expected =
                            if name = "both" then
                              match expected with
                              | Returned (Ok _) -> Returned (Ok [])
                              | other -> other
                            else expected
                          in
                          let label =
                            Printf.sprintf "%s [%s] delays [%s]" name
                              (String.concat "; " (List.map show outcomes))
                              (String.concat "; " (List.map string_of_int delays))
                          in
                          same_observation label expected actual;
                          if !live <> 0 then Alcotest.failf "leaked fibers: %s" label)
                    (permutations (List.init n Fun.id)))
                (outcome_space n))
            combinators;
          check_bool "enough cases exercised" true (!cases > 300)))

let race_expected cells =
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) cells in
  let rec scan = function
    | [] -> None
    | (_, Value v) :: _ -> Some (Returned (Ok v))
    | (_, Raise ex) :: _ -> Some (Raised ex)
    | _ :: rest -> scan rest
  in
  match scan sorted with
  | Some _ as decided -> decided
  | None ->
      if List.exists (fun (_, o) -> o = Block) cells then None
      else
        let fails =
          List.map (function _, Typed e -> Cause.Fail e | _ -> assert false) cells
        in
        Some
          (Returned
             (Error (match fails with [ one ] -> one | many -> Cause.Concurrent many)))

let race_first_expected cells =
  let settled = List.filter (fun (_, o) -> o <> Block) cells in
  match List.sort (fun (a, _) (b, _) -> compare a b) settled with
  | [] -> None
  | (_, Value v) :: _ -> Some (Returned (Ok v))
  | (_, Typed e) :: _ -> Some (Returned (Error e))
  | (_, Raise ex) :: _ -> Some (Raised ex)
  | (_, Block) :: _ -> assert false

let law_race () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let cases = ref 0 in
          List.iter
            (fun n ->
              List.iter
                (fun outcomes ->
                  List.iter
                    (fun delays ->
                      let cells = List.combine delays outcomes in
                      let label kind =
                        Printf.sprintf "%s [%s] delays [%s]" kind
                          (String.concat "; " (List.map show outcomes))
                          (String.concat "; " (List.map string_of_int delays))
                      in
                      let tasks () = List.map (fun (delay, o) -> branch ~delay o) cells in
                      (match race_expected cells with
                      | None -> ()
                      | Some expected ->
                          incr cases;
                          live := 0;
                          let actual =
                            observe (fun () -> Concurrent.race ~sw (tasks ()))
                          in
                          same_observation (label "race") expected actual;
                          if !live <> 0 then
                            Alcotest.failf "leaked fibers: %s" (label "race"));
                      match race_first_expected cells with
                      | None -> ()
                      | Some expected ->
                          incr cases;
                          live := 0;
                          let actual =
                            observe (fun () -> Concurrent.race_first ~sw (tasks ()))
                          in
                          same_observation (label "race_first") expected actual;
                          if !live <> 0 then
                            Alcotest.failf "leaked fibers: %s" (label "race_first"))
                    (permutations (List.init n Fun.id)))
                (outcome_space n))
            [ 2; 3 ];
          check_bool "enough cases exercised" true (!cases > 300)))

type bg = Bg_ok | Bg_typed of string | Bg_raise of exn | Bg_block

let law_with_background () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let cases = ref 0 in
          let bgs i =
            [ Bg_ok; Bg_typed (Printf.sprintf "bg%d" i); Bg_raise (Boom "bgx"); Bg_block ]
          in
          List.iter
            (fun (bg_delay, body_delay) ->
              List.iter
                (fun bg ->
                  List.iter
                    (fun body ->
                      let bg_fails =
                        match bg with Bg_typed _ | Bg_raise _ -> true | _ -> false
                      in
                      let bg_result =
                        match bg with
                        | Bg_typed e -> Some (Returned (Error e))
                        | Bg_raise ex -> Some (Raised ex)
                        | _ -> None
                      in
                      let body_result =
                        match body with
                        | Value v -> Some (Returned (Ok v))
                        | Typed e -> Some (Returned (Error e))
                        | Raise ex -> Some (Raised ex)
                        | Block -> None
                      in
                      let expected =
                        match (bg_fails, body_result) with
                        | true, None -> bg_result
                        | true, Some _ when bg_delay < body_delay -> bg_result
                        | _, (Some _ as decided) -> decided
                        | false, None -> None
                      in
                      match expected with
                      | None -> ()
                      | Some expected ->
                          incr cases;
                          live := 0;
                          let background () : (unit, string) result =
                            counted (fun () ->
                                yields bg_delay;
                                match bg with
                                | Bg_ok -> Ok ()
                                | Bg_typed e -> Error e
                                | Bg_raise ex -> raise ex
                                | Bg_block -> Eio.Fiber.await_cancel ())
                          in
                          let actual =
                            observe (fun () ->
                                Concurrent.with_background ~sw background
                                  (branch ~delay:body_delay body))
                          in
                          let label =
                            Printf.sprintf "with_background bg=%s@%d body=%s@%d"
                              (match bg with
                              | Bg_ok -> "ok"
                              | Bg_typed e -> e
                              | Bg_raise _ -> "raise"
                              | Bg_block -> "block")
                              bg_delay (show body) body_delay
                          in
                          same_observation label expected actual;
                          if !live <> 0 then Alcotest.failf "leaked fibers: %s" label)
                    (List.init 4 (fun kind ->
                         match kind with
                         | 0 -> Value 7
                         | 1 -> Typed "body"
                         | 2 -> Raise (Boom "bodyx")
                         | _ -> Block)))
                (bgs 0))
            [ (0, 1); (1, 0); (2, 1); (1, 2) ];
          check_bool "enough cases exercised" true (!cases > 30)))

(* ---- nsup-zzhl: race and race_first ----------------------------------------------------- *)

let race_variants () =
  with_outer (fun sw ->
      (* the first success wins over earlier errors; losers are awaited *)
      let result =
        Concurrent.race ~sw
          [
            (fun () -> Error "a");
            blocked;
            (fun () ->
              yields 2;
              Ok 9);
          ]
      in
      check_bool "first success" true (result = Ok 9);
      census "race success";
      (* all fail: input order, whatever the settling order *)
      let result =
        Concurrent.race ~sw
          [
            (fun () ->
              yields 3;
              Error "slow-first");
            (fun () -> Error "fast-second");
            (fun () ->
              yields 1;
              Error "middle-third");
          ]
      in
      (match result with
      | Error
          (Cause.Concurrent
             [
               Cause.Fail "slow-first";
               Cause.Fail "fast-second";
               Cause.Fail "middle-third";
             ]) ->
          ()
      | _ -> Alcotest.fail "Concurrent causes in input order");
      (* race_first: the first settled result of either kind *)
      let result =
        Concurrent.race_first ~sw
          [
            blocked;
            (fun () ->
              yields 1;
              Error "settled-first");
            (fun () ->
              yields 2;
              Ok 1);
          ]
      in
      check_bool "race_first returns an early Error" true (result = Error "settled-first");
      census "race_first error";
      let result =
        Concurrent.race_first ~sw
          [
            blocked;
            (fun () ->
              yields 1;
              Ok 5);
            (fun () ->
              yields 2;
              Error "later");
          ]
      in
      check_bool "race_first returns an early Ok" true (result = Ok 5);
      census "race_first ok";
      match Concurrent.race_first ~sw [] with
      | exception Invalid_argument _ -> ()
      | _ -> Alcotest.fail "race_first accepted no branches")

(* ---- nsup-q444: the 2026-09-28 regressions, against the rewritten combinators ---------- *)

let regression_identity_through_daemons () =
  with_outer (fun _ ->
      (* identity lost through daemons: the caller's private identity must reach Scope.run
         through with_background's daemon and through a supervised scope's daemons. *)
      let id, outcome =
        cancelled_caller (fun sw ->
            Concurrent.with_background ~sw blocked (fun () -> Eio.Fiber.await_cancel ()))
      in
      check_bool "with_background daemon" true (is_interrupt id outcome);
      let id, outcome =
        cancelled_caller (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                Scope.fork_daemon scope (fun () -> blocked ());
                ignore (Scope.fork_error scope blocked);
                Eio.Fiber.await_cancel ()))
      in
      check_bool "supervised daemon" true (is_interrupt id outcome);
      census "identity")

let regression_half_frame () =
  with_outer (fun sw ->
      (* half-frame on a cancelled write: a loser inside a protected two-part write finishes
         the frame before the race returns *)
      let wire = Buffer.create 8 in
      let loser () : (int, string) result =
        counted (fun () ->
            Eio.Cancel.protect (fun () ->
                Buffer.add_string wire "H";
                Eio.Fiber.yield ();
                Buffer.add_string wire "P");
            Eio.Fiber.await_cancel ())
      in
      let result = Concurrent.race ~sw [ loser; (fun () -> Ok 1) ] in
      check_bool "winner" true (result = Ok 1);
      Alcotest.(check string) "whole frame written" "HP" (Buffer.contents wire);
      census "half frame")

let regression_exporter_queue () =
  with_outer (fun sw ->
      (* exporter losing its queue: a background worker drains what is queued when the body
         ends, and with_background returns only after the drain *)
      let queue = ref [ 1; 2; 3 ] and exported = ref [] in
      let worker () : (unit, string) result =
        Fun.protect
          (fun () -> Eio.Fiber.await_cancel ())
          ~finally:(fun () ->
            Eio.Cancel.protect (fun () ->
                List.iter
                  (fun item ->
                    Eio.Fiber.yield ();
                    exported := item :: !exported)
                  !queue;
                queue := []))
      in
      let result = Concurrent.with_background ~sw worker (fun () -> Ok "body") in
      check_bool "body result" true (result = Ok "body");
      Alcotest.(check (list int)) "queue exported exactly once" [ 3; 2; 1 ] !exported;
      check_bool "queue empty" true (!queue = []))

(* ---- nsup-pzj6: Retry policy ------------------------------------------------------------- *)

let retry_policy () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let elapsed start = Eio.Time.now clock -. start in
      (* default policy: today's behaviour *)
      let tries = ref 0 in
      let result =
        Retry.retry ~clock (Schedule.recurs 2) (fun () ->
            incr tries;
            Error "x")
      in
      check_bool "default retries errors until the schedule ends" true (result = Error "x");
      check_int "three attempts" 3 !tries;
      check_bool "default: Ok returns at once" true
        (Retry.retry ~clock (Schedule.recurs 5) (fun () -> Ok 1) = Ok 1);
      (* is_success: an Ok that does not satisfy it is retried *)
      tries := 0;
      let start = Eio.Time.now clock in
      let policy = { Retry.default_policy with is_success = (fun v -> v >= 3) } in
      let result =
        Retry.retry ~clock ~policy
          (Schedule.spaced (Duration.ms 10))
          (fun () ->
            incr tries;
            Ok !tries)
      in
      check_bool "successful-looking reply retried until it is a success" true
        (result = Ok 3);
      check_int "three attempts" 3 !tries;
      Alcotest.(check (float 0.00001)) "two virtual delays" 0.02 (elapsed start);
      (* schedule exhausted on an unsuccessful Ok: the last result comes back unchanged *)
      tries := 0;
      let policy = { Retry.default_policy with is_success = (fun _ -> false) } in
      let result =
        Retry.retry ~clock ~policy (Schedule.recurs 2) (fun () ->
            incr tries;
            Ok !tries)
      in
      check_bool "last Ok returned" true (result = Ok 3);
      (* is_worth_retrying: a hopeless error fails fast *)
      tries := 0;
      let start = Eio.Time.now clock in
      let policy =
        { Retry.default_policy with is_worth_retrying = (fun e -> e <> "fatal") }
      in
      let result =
        Retry.retry ~clock ~policy
          (Schedule.spaced (Duration.seconds 1))
          (fun () ->
            incr tries;
            Error "fatal")
      in
      check_bool "fails fast" true (result = Error "fatal");
      check_int "one attempt" 1 !tries;
      Alcotest.(check (float 0.00001)) "no sleep" 0.0 (elapsed start);
      tries := 0;
      let result =
        Retry.retry ~clock ~policy (Schedule.recurs 5) (fun () ->
            incr tries;
            if !tries < 3 then Error "again" else Error "fatal")
      in
      check_bool "worth retrying until it is not" true (result = Error "fatal");
      check_int "three attempts" 3 !tries;
      (* on_retry: attempt number and the attempt's result, before each sleep *)
      tries := 0;
      let seen = ref [] in
      let policy =
        {
          Retry.is_success = (fun _ -> true);
          is_worth_retrying = (fun _ -> true);
          on_retry = (fun attempt result -> seen := (attempt, result) :: !seen);
        }
      in
      let result =
        Retry.retry ~clock ~policy (Schedule.recurs 2) (fun () ->
            incr tries;
            if !tries < 3 then Error (Printf.sprintf "e%d" !tries) else Ok "done")
      in
      check_bool "eventually Ok" true (result = Ok "done");
      check_bool "on_retry saw each failed attempt" true
        (List.rev !seen = [ (1, Error "e1"); (2, Error "e2") ]);
      seen := [];
      check_bool "exhaustion returns the final attempt error" true
        (Retry.retry ~clock ~policy (Schedule.recurs 1) (fun () -> Error "e") = Error "e");
      check_int "on_retry is not called when the schedule ends" 1 (List.length !seen);
      (* the schedule's input is the attempt's result *)
      tries := 0;
      let result =
        Retry.retry ~clock
          ~policy:{ Retry.default_policy with is_success = (fun _ -> false) }
          (Schedule.recur_until (function Ok v -> v >= 2 | Error _ -> false))
          (fun () ->
            incr tries;
            Ok !tries)
      in
      check_bool "schedule sees Ok attempts" true (result = Ok 2))

(* ---- nsup-69fi: Schedule vocabulary ------------------------------------------------------ *)

let run_schedule schedule n =
  let rec go driver i acc =
    if i = 0 then (List.rev acc, false)
    else
      match Schedule.step ~now_ms:0 ~input:() driver with
      | Schedule.Continue m, next -> go next (i - 1) (Duration.to_ms m.delay :: acc)
      | Schedule.Done _, _ -> (List.rev acc, true)
  in
  go (Schedule.start schedule) n []

let ms = Duration.ms

let schedule_vocabulary () =
  let delays_ = Alcotest.(check (pair (list int) bool)) in
  delays_ "intervals"
    ([ 10; 20; 30 ], true)
    (run_schedule (Schedule.intervals [ ms 10; ms 20; ms 30 ]) 10);
  delays_ "intervals empty" ([], true) (run_schedule (Schedule.intervals []) 10);
  delays_ "max_interval"
    ([ 100; 200; 300; 300 ], false)
    (run_schedule (Schedule.max_interval (ms 300) (Schedule.exponential (ms 100))) 4);
  delays_ "with_initial_delay"
    ([ 5; 100; 100 ], false)
    (run_schedule (Schedule.with_initial_delay (ms 5) (Schedule.spaced (ms 100))) 3);
  delays_ "with_no_initial_delay"
    ([ 0; 100; 100 ], false)
    (run_schedule (Schedule.with_no_initial_delay (Schedule.spaced (ms 100))) 3);
  delays_ "initial delay does not resurrect a finished schedule" ([], true)
    (run_schedule (Schedule.with_initial_delay (ms 5) (Schedule.recurs 0)) 3);
  delays_ "cumulative delay stops before the sum exceeds the limit"
    ([ 100; 100 ], true)
    (run_schedule
       (Schedule.max_retries_by_cumulative_delay (ms 250) (Schedule.spaced (ms 100)))
       10);
  delays_ "cumulative delay limit is inclusive"
    ([ 100; 100; 100 ], true)
    (run_schedule
       (Schedule.max_retries_by_cumulative_delay (ms 300) (Schedule.spaced (ms 100)))
       10);
  (* decorrelated jitter: bounded by min and max, and by 3 * the previous delay *)
  let sample () =
    fst
      (run_schedule
         (Schedule.decorrelated_jitter ~random:(Random.State.make [| 42 |]) ~min:(ms 100)
            ~max:(ms 1000))
         300)
  in
  let delays = sample () in
  check_int "runs forever" 300 (List.length delays);
  Alcotest.(check (list int)) "reproducible from a seed" delays (sample ());
  let previous = ref 100 in
  List.iter
    (fun delay ->
      check_bool "at least min" true (delay >= 100);
      check_bool "at most max" true (delay <= 1000);
      check_bool "at most 3 * previous" true (delay <= 3 * !previous);
      previous := delay)
    delays;
  check_bool "actually varies" true (List.length (List.sort_uniq compare delays) > 20);
  (match
     Schedule.decorrelated_jitter ~random:(Random.State.make [| 42 |]) ~min:(ms 5)
       ~max:(ms 1)
   with
  | exception Invalid_argument _ -> ()
  | _ -> Alcotest.fail "reversed decorrelated bounds accepted");
  (* jitter kinds *)
  let kind_samples ?(n = 400) kind base =
    fst
      (run_schedule
         (Schedule.jittered ~random:(Random.State.make [| 7 |]) ~kind
            (Schedule.spaced (ms base)))
         n)
  in
  let full = kind_samples Schedule.Full 1000 in
  check_bool "full within [0, delay]" true
    (List.for_all (fun d -> d >= 0 && d <= 1000) full);
  check_bool "full spreads across the range" true
    (List.exists (fun d -> d < 200) full && List.exists (fun d -> d > 800) full);
  let equal = kind_samples Schedule.Equal 1000 in
  check_bool "equal within [delay/2, delay]" true
    (List.for_all (fun d -> d >= 500 && d <= 1000) equal);
  check_bool "equal spreads across its half" true
    (List.exists (fun d -> d < 600) equal && List.exists (fun d -> d > 900) equal);
  let decorrelated = kind_samples ~n:30 Schedule.Decorrelated 100 in
  let previous = ref 100 in
  List.iter
    (fun delay ->
      check_bool "decorrelated within [base, 3 * previous]" true
        (delay >= 100 && delay <= 3 * !previous);
      previous := delay)
    decorrelated;
  (match
     Schedule.jittered ~random:(Random.State.make [| 7 |]) ~kind:Schedule.Full ~min:0.5
       (Schedule.spaced (ms 1))
   with
  | exception Invalid_argument _ -> ()
  | _ -> Alcotest.fail "~kind with ~min accepted");
  (* a finished inner schedule stays finished under a jitter kind *)
  delays_ "jitter kind on a finite schedule" ([ 0 ], true)
    (run_schedule
       (Schedule.jittered ~random:(Random.State.make [| 1 |]) ~kind:Schedule.Full
          (Schedule.both (Schedule.recurs 1) (Schedule.spaced (ms 0))))
       5)

(* ---- nsup-gxmx: Timeout is an alias of Eio; no Resource module -------------------------- *)

let timeout_alias ~(caps : < Ox_caps.Cap.fs_read ; .. >) () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let slow () =
        Eio.Time.sleep clock 1.0;
        Ok "late"
      in
      let ours = Timeout.timeout ~clock (Duration.ms 100) slow in
      let theirs : (string, [ `Timeout ]) result =
        Eio.Time.with_timeout clock 0.1 (fun () ->
            (slow () : (string, [> `Timeout ]) result))
      in
      check_bool "same outcome as Eio.Time.with_timeout" true
        (ours = theirs && ours = Error `Timeout);
      check_bool "fast body passes through" true
        (Timeout.timeout ~clock (Duration.ms 100) (fun () -> Ok 1) = Ok 1));
  let lib = if Sys.file_exists "lib/ox/dune" then "lib/ox" else "../../lib/ox" in
  (* Row 46 (nfloor-elwp) brought back a Resource module of a different shape:
     use_in_scope over Switch.on_release. acquire_release stays gone. *)
  let resource_mli = Filename.concat lib "resource.mli" in
  if Sys.file_exists resource_mli then begin
    let channel = Ox_caps.Cap_stdlib.open_in ~caps resource_mli in
    let text =
      Fun.protect
        (fun () -> really_input_string channel (in_channel_length channel))
        ~finally:(fun () -> close_in channel)
    in
    let needle = "val acquire_release" in
    let n = String.length needle in
    let rec mentions i =
      i + n <= String.length text && (String.sub text i n = needle || mentions (i + 1))
    in
    check_bool "Resource.acquire_release is gone" false (mentions 0)
  end;
  Eio_main.run (fun _ ->
      let order = ref [] in
      Eio.Switch.run (fun sw ->
          Eio.Switch.on_release sw (fun () -> order := 1 :: !order);
          Eio.Switch.on_release sw (fun () -> order := 2 :: !order));
      Alcotest.(check (list int)) "Switch.on_release runs in reverse" [ 1; 2 ] !order)

(* ---- nsup-o65j nsup-hje5: the doctrine is written down ---------------------------------- *)

let doctrine_docs ~(caps : < Ox_caps.Cap.fs_read ; .. >) () =
  let docs = if Sys.file_exists "docs/why-ox.md" then "docs" else "../../docs" in
  let read name =
    let channel = Ox_caps.Cap_stdlib.open_in ~caps (Filename.concat docs name) in
    Fun.protect
      (fun () -> really_input_string channel (in_channel_length channel))
      ~finally:(fun () -> close_in channel)
  in
  let contains haystack needle =
    let n = String.length needle in
    let rec scan i =
      i + n <= String.length haystack && (String.sub haystack i n = needle || scan (i + 1))
    in
    scan 0
  in
  let why = read "why-ox.md" and modes = read "modes.md" in
  List.iter
    (fun phrase -> check_bool ("why-ox.md: " ^ phrase) true (contains why phrase))
    [
      "Unrecoverable errors";
      "Recoverable errors";
      "as small as possible";
      "supervised_error";
    ];
  List.iter
    (fun phrase -> check_bool ("modes.md: " ^ phrase) true (contains modes phrase))
    [ "handled_effect"; "supervised_error"; "Switch.run"; "Fiber.fork" ]

let tests =
  [
    ( "Supervised scopes nsup-xkke nsup-hm4o nsup-xzl3 nsup-1lzt nsup-a4bf nsup-5j80",
      [
        Alcotest.test_case "nsup-xkke nsup-a4bf a typed error ends the scope" `Quick
          error_ends_scope;
        Alcotest.test_case "nsup-hm4o plain forks and daemons" `Quick plain_forks;
        Alcotest.test_case "nsup-xzl3 fork handles await" `Quick await_handle;
        Alcotest.test_case "nsup-1lzt exceptions end the scope untouched" `Quick
          exceptions;
        Alcotest.test_case "nsup-5j80 caller cancellation propagates" `Quick cancellation;
      ] );
    ( "Concurrent over Eio nsup-hd24 nsup-i1zm nsup-zzhl nsup-q444",
      [
        Alcotest.test_case
          "nsup-hd24 nsup-q444 cancelling the caller cancels every combinator" `Quick
          combinators_cancel;
        Alcotest.test_case "nsup-hd24 for_each" `Quick for_each;
        Alcotest.test_case "nsup-i1zm law: par both all for_each" `Quick law_group;
        Alcotest.test_case "nsup-i1zm law: race race_first" `Quick law_race;
        Alcotest.test_case "nsup-i1zm law: with_background" `Quick law_with_background;
        Alcotest.test_case "nsup-zzhl race and race_first" `Quick race_variants;
        Alcotest.test_case "nsup-q444 identity through daemons" `Quick
          regression_identity_through_daemons;
        Alcotest.test_case "nsup-q444 half frame on cancelled write" `Quick
          regression_half_frame;
        Alcotest.test_case "nsup-q444 exporter keeps its queue" `Quick
          regression_exporter_queue;
      ] );
    ( "Retry and Schedule nsup-pzj6 nsup-69fi nsup-gxmx nsup-o65j nsup-hje5",
      [
        Alcotest.test_case "nsup-pzj6 retry policy" `Quick retry_policy;
        Alcotest.test_case "nsup-69fi schedule vocabulary" `Quick schedule_vocabulary;
        Alcotest.test_case "nsup-gxmx timeout alias, no Resource module" `Quick (fun () ->
            timeout_alias ~caps:(Ox_test.powerbox ()) ());
        Alcotest.test_case "nsup-o65j nsup-hje5 doctrine in docs" `Quick (fun () ->
            doctrine_docs ~caps:(Ox_test.powerbox ()) ());
      ] );
  ]
