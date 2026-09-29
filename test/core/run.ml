open Ox

let expect_success = function
  | Exit.Success _ -> ()
  | Exit.Failure c ->
      Alcotest.failf "expected success: %a" (Cause.pp Format.pp_print_string) c

let expect_fail expected = function
  | Exit.Failure (Cause.Fail error) ->
      Alcotest.(check string) "typed cause" expected error
  | Exit.Failure c ->
      Alcotest.failf "expected Fail: %a" (Cause.pp Format.pp_print_string) c
  | Exit.Success _ -> Alcotest.fail "expected failure"

let test_result_syntax () =
  let open Result.Syntax in
  let outcome =
    let* x = Ok 2 in
    let+ y = Ok 3 in
    x + y
  in
  Alcotest.(check (result int string)) "syntax" (Ok 5) outcome;
  let outcome =
    let* _ = Error "stop" in
    Ok 99
  in
  Alcotest.(check (result int string)) "short circuit" (Error "stop") outcome

let test_cause_exit () =
  let id = Interrupt_id.create () in
  let other = Interrupt_id.create () in
  Alcotest.(check bool) "different identity" false (Interrupt_id.equal id other);
  Alcotest.(check bool) "printable" true (String.length (Interrupt_id.to_string id) > 0);
  let cause =
    Cause.Suppressed
      {
        primary = Cause.Fail "typed";
        finalizer =
          Cause.Finalizer (Cause.Die (Failure "cleanup", Printexc.get_callstack 4));
      }
  in
  let rendered = Format.asprintf "%a" (Cause.pp Format.pp_print_string) cause in
  Alcotest.(check bool) "nested typed payload" true (String.contains rendered 't');
  let compact = Format.asprintf "%a" (Cause.pp_compact Format.pp_print_string) cause in
  Alcotest.(check bool) "compact one line" false (String.contains compact '\n');
  Alcotest.(check int) "failure code" 1 (Exit.process_code (Exit.Failure cause));
  Alcotest.(check int)
    "interrupt process code" 130
    (Exit.process_code (Exit.Failure (Cause.Interrupt (Some id))));
  Alcotest.(check bool)
    "interrupt only" true
    (Exit.is_interrupt_only (Exit.Failure (Cause.Interrupt None)));
  Alcotest.(check bool)
    "defect not handled" true
    (match Exit.to_result (Exit.Failure cause) with Error _ -> true | _ -> false);
  Alcotest.(check bool)
    "typed handled" true
    (match Exit.to_result (Exit.Failure (Cause.Fail "typed")) with
    | Ok (Error "typed") -> true
    | _ -> false);
  let printed_exit =
    Format.asprintf "%a"
      (Exit.pp Format.pp_print_int Format.pp_print_string)
      (Exit.Success 9)
  in
  Alcotest.(check string) "exit printer" "Success(9)" printed_exit

let test_scope_classification () =
  Eio_main.run (fun _ ->
      expect_fail "typed" (Scope.run (fun _ -> Error "typed"));
      (match Scope.run (fun _ -> raise (Failure "bad")) with
      | Exit.Failure (Cause.Die (Failure _, bt)) ->
          Alcotest.(check bool)
            "backtrace" true
            (String.length (Printexc.raw_backtrace_to_string bt) > 0)
      | _ -> Alcotest.fail "escaped exception not Die");
      (match Scope.run (fun _ -> raise (Eio.Cancel.Cancelled (Failure "outside"))) with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | _ -> Alcotest.fail "external interruption identity");
      let id = Interrupt_id.create () in
      (match Scope.run (fun _ -> raise (Eio.Cancel.Cancelled (Interrupt_id.stop id))) with
      | Exit.Failure (Cause.Interrupt (Some seen)) ->
          Alcotest.(check bool) "own stop id" true (Interrupt_id.equal id seen)
      | _ -> Alcotest.fail "own stop not classified");
      (* ^napp-78pf: Eio may wrap a switch cancellation again in live fibers. *)
      let rec wrap depth reason =
        if depth = 0 then reason else Eio.Cancel.Cancelled (wrap (depth - 1) reason)
      in
      List.iter
        (fun depth ->
          (match Scope.run (fun _ -> raise (wrap depth (Interrupt_id.stop id))) with
          | Exit.Failure (Cause.Interrupt (Some seen)) ->
              Alcotest.(check bool) "nested stop id" true (Interrupt_id.equal id seen)
          | _ -> Alcotest.fail "nested stop not classified");
          match Scope.run (fun _ -> raise (wrap depth (Failure "outside"))) with
          | Exit.Failure (Cause.Interrupt None) -> ()
          | _ -> Alcotest.fail "nested external cancellation gained an identity")
        [ 2; 3 ];
      (match
         Scope.run (fun sw ->
             Eio.Switch.on_release sw (fun () -> failwith "release");
             Ok ())
       with
      | Exit.Failure (Cause.Finalizer (Cause.Die (Failure _, _))) -> ()
      | _ -> Alcotest.fail "release after success");
      match
        Scope.run (fun sw ->
            Eio.Switch.on_release sw (fun () -> failwith "release");
            Error "typed")
      with
      | Exit.Failure
          (Cause.Suppressed
             { primary = Cause.Fail "typed"; finalizer = Cause.Die (Failure _, _) }) ->
          ()
      | _ -> Alcotest.fail "release after failure")

let test_scope_child_defect () =
  Eio_main.run (fun _ ->
      (match
         Scope.run (fun sw ->
             Eio.Fiber.fork ~sw (fun () ->
                 Eio.Fiber.yield ();
                 failwith "child");
             Ok ())
       with
      | Exit.Failure (Cause.Die (Failure _, bt)) ->
          Alcotest.(check bool)
            "forked defect backtrace retained" true
            (String.length (Printexc.raw_backtrace_to_string bt) > 0)
      | actual ->
          Alcotest.failf "forked failure misclassified as finalizer: %a"
            (Exit.pp (fun _ () -> ()) Format.pp_print_string)
            actual);
      let outside = Failure "outside" in
      let canceled =
        Eio.Cancel.sub (fun context ->
            Eio.Switch.run (fun outer ->
                Eio.Fiber.fork ~sw:outer (fun () ->
                    Eio.Fiber.yield ();
                    Eio.Cancel.cancel context outside);
                Scope.run (fun sw ->
                    Eio.Fiber.fork ~sw (fun () -> Eio.Fiber.await_cancel ());
                    Eio.Fiber.await_cancel ())))
      in
      (match canceled with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | actual ->
          Alcotest.failf "parent cancellation misclassified as child defect: %a"
            (Exit.pp (fun _ () -> ()) Format.pp_print_string)
            actual);
      let same = Failure "same" in
      (match
         Scope.run (fun sw ->
             Eio.Switch.fail sw same;
             raise same)
       with
      | Exit.Failure (Cause.Die (ex, _)) when ex == same -> ()
      | _ -> Alcotest.fail "same body and switch defect duplicated");
      let same_multiple = Failure "multiple" in
      (match
         Scope.run (fun sw ->
             Eio.Switch.fail sw
               (Eio.Exn.Multiple [ (same_multiple, Printexc.get_callstack 3) ]);
             raise same_multiple)
       with
      | Exit.Failure (Cause.Die (ex, _)) when ex == same_multiple -> ()
      | _ -> Alcotest.fail "same defect in Eio Multiple duplicated");
      let group = Eio.Exn.Multiple [ (Failure "one", Printexc.get_callstack 3) ] in
      (match
         Scope.run (fun sw ->
             Eio.Switch.fail sw group;
             raise group)
       with
      | Exit.Failure (Cause.Die (ex, _)) when ex == group -> ()
      | _ -> Alcotest.fail "physically identical Multiple duplicated");
      let grouped_child =
        Eio.Exn.Multiple [ (Failure "grouped child", Printexc.get_callstack 3) ]
      in
      (match
         Scope.run (fun sw ->
             Eio.Fiber.fork ~sw (fun () ->
                 Eio.Fiber.yield ();
                 raise grouped_child);
             Ok ())
       with
      | Exit.Failure (Cause.Die (ex, _)) when ex == grouped_child -> ()
      | _ -> Alcotest.fail "aggregated child defect classified as cleanup");
      let child = Failure "typed child" in
      (match
         Scope.run (fun sw ->
             Eio.Fiber.fork ~sw (fun () ->
                 Eio.Fiber.yield ();
                 raise child);
             Error "typed")
       with
      | Exit.Failure (Cause.Concurrent [ Cause.Fail "typed"; Cause.Die (ex, _) ])
        when ex == child ->
          ()
      | _ -> Alcotest.fail "typed error and child defect must not become release error");
      let child = Failure "child before release" in
      let release = Failure "release after child" in
      match
        Scope.run (fun sw ->
            Eio.Switch.on_release sw (fun () -> raise release);
            Eio.Fiber.fork ~sw (fun () ->
                Eio.Fiber.yield ();
                raise child);
            Ok ())
      with
      | Exit.Failure
          (Cause.Suppressed
             { primary = Cause.Die (ex, _); finalizer = Cause.Die (fin, _) })
        when ex == child && fin == release ->
          ()
      | _ -> Alcotest.fail "child defect and later release must remain distinct")

let test_resource () =
  Eio_main.run (fun _ ->
      let order = ref [] in
      let outcome =
        Scope.run (fun sw ->
            let acquire n =
              Support.acquire_release ~sw
                ~acquire:(fun () -> Ok n)
                ~release:(fun n -> order := n :: !order)
            in
            match (acquire 1, acquire 2) with Ok _, Ok _ -> Ok () | _ -> Error "acquire")
      in
      expect_success outcome;
      Alcotest.(check (list int)) "reverse release" [ 1; 2 ] !order;
      let failed_acquire = ref false in
      expect_fail "failed"
        (Scope.run (fun sw ->
             Support.acquire_release ~sw
               ~acquire:(fun () -> Error "failed")
               ~release:(fun _ -> failed_acquire := true)));
      Alcotest.(check bool) "nothing acquired" false !failed_acquire;
      match
        Scope.run (fun sw ->
            let _ =
              Support.acquire_release ~sw
                ~acquire:(fun () -> Ok 1)
                ~release:(fun _ -> failwith "cleanup")
            in
            Error "primary")
      with
      | Exit.Failure
          (Cause.Suppressed
             { primary = Cause.Fail "primary"; finalizer = Cause.Die (Failure _, _) }) ->
          ()
      | _ -> Alcotest.fail "resource release suppression")

let test_timeout_mock () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let start = Eio.Time.now clock in
      let cleaned = ref false in
      let result =
        Timeout.timeout ~clock (Duration.ms 250) (fun () ->
            Eio.Switch.run (fun sw ->
                Eio.Switch.on_release sw (fun () -> cleaned := true);
                Eio.Time.sleep clock 1.;
                Ok 9))
      in
      Alcotest.(
        check (result int (of_pp (fun fmt _ -> Format.pp_print_string fmt "timeout"))))
        "timed out" (Error `Timeout) result;
      Alcotest.(check bool) "timed out body finalizer awaited" true !cleaned;
      Alcotest.(check (float 0.00001))
        "virtual deadline" 0.25
        (Eio.Time.now clock -. start);
      let finished = ref false in
      let result =
        Timeout.timeout ~clock (Duration.ms 10) (fun () ->
            finished := true;
            Ok 4)
      in
      Alcotest.(check bool) "body ended" true !finished;
      Alcotest.(check bool) "success" true (result = Ok 4))

let test_retry_repeat_mock () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let start = Eio.Time.now clock in
      let calls = ref 0 in
      let result =
        Retry.retry ~clock
          (Schedule.spaced (Duration.ms 30))
          (fun () ->
            incr calls;
            if !calls < 3 then Error "again" else Ok 7)
      in
      Alcotest.(check (result int string)) "retry succeeds" (Ok 7) result;
      Alcotest.(check int) "three attempts" 3 !calls;
      Alcotest.(check (float 0.00001))
        "retry virtual clock" 0.06
        (Eio.Time.now clock -. start);
      let last = ref 0 in
      let result =
        Retry.retry ~clock (Schedule.recurs 2) (fun () ->
            incr last;
            Error "last")
      in
      Alcotest.(check (result int string)) "retry last typed error" (Error "last") result;
      Alcotest.(check int) "retry stops at policy" 3 !last;
      let repeats = ref 0 in
      let start = Eio.Time.now clock in
      let result =
        Retry.repeat ~clock
          (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.ms 40)))
          (fun () ->
            incr repeats;
            Ok !repeats)
      in
      Alcotest.(check bool) "repeat returns schedule output" true (result = Ok (2, 2));
      Alcotest.(check int) "repeat three iterations" 3 !repeats;
      Alcotest.(check (float 0.00001))
        "repeat virtual clock" 0.08
        (Eio.Time.now clock -. start);
      let failures = ref 0 in
      let result =
        Retry.repeat ~clock (Schedule.recurs 3) (fun () ->
            incr failures;
            if !failures = 2 then Error "stop" else Ok !failures)
      in
      Alcotest.(check (result int string)) "repeat stops on error" (Error "stop") result;
      Alcotest.(check int) "repeat stops after failure" 2 !failures)

let test_loop_cancel_mock () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let verify label loop =
        let finished = ref false in
        let start = Eio.Time.now clock in
        let winner =
          Eio.Fiber.first
            (fun () ->
              Fun.protect
                (fun () ->
                  ignore (loop ());
                  -1)
                ~finally:(fun () -> finished := true))
            (fun () ->
              Eio.Time.sleep clock 0.01;
              1)
        in
        Alcotest.(check int) label 1 winner;
        Alcotest.(check bool) "sleeping fiber awaited" true !finished;
        Alcotest.(check (float 0.00001))
          "no full backoff" 0.01
          (Eio.Time.now clock -. start)
      in
      verify "retry interrupted" (fun () ->
          Retry.retry ~clock
            (Schedule.spaced (Duration.seconds 1))
            (fun () -> Error "try"));
      verify "repeat interrupted" (fun () ->
          Retry.repeat ~clock (Schedule.spaced (Duration.seconds 1)) (fun () -> Ok ())))

let with_fiber_census f =
  Eio_main.run (fun _ ->
      let alive = ref 0 in
      let fork ~sw body =
        Eio.Fiber.fork ~sw (fun () ->
            incr alive;
            Fun.protect body ~finally:(fun () -> decr alive))
      in
      f fork;
      Alcotest.(check int) "ncore-mvvi no live child fibers" 0 !alive)

let test_race () =
  with_fiber_census (fun fork ->
      Eio.Switch.run (fun sw ->
          let cleaned = ref false in
          let result =
            Concurrent.race ~sw
              [
                (fun () ->
                  Eio.Switch.run (fun child ->
                      Eio.Switch.on_release child (fun () -> cleaned := true);
                      Eio.Fiber.await_cancel ()));
                (fun () ->
                  Eio.Fiber.yield ();
                  Ok 7);
              ]
          in
          Alcotest.(check bool) "first success" true (result = Ok 7);
          Alcotest.(check bool) "loser finalizer completed" true !cleaned;
          ignore fork))

let test_race_cause () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          (match
             Concurrent.race ~sw
               [
                 (fun () -> Error "a");
                 (fun () ->
                   Eio.Fiber.yield ();
                   Error "b");
               ]
           with
          | Error (Cause.Concurrent [ Cause.Fail "a"; Cause.Fail "b" ]) -> ()
          | _ -> Alcotest.fail "all-fail cause order");
          (* nsup-i1zm: a defect is raised as it is, not collected as a Cause.Die *)
          (match
             Concurrent.race ~sw [ (fun () -> Error "a"); (fun () -> failwith "boom") ]
           with
          | exception Failure msg when msg = "boom" -> ()
          | _ -> Alcotest.fail "race must raise a branch defect unchanged");
          (match Concurrent.race ~sw [ (fun () -> Error "only") ] with
          | Error (Cause.Fail "only") -> ()
          | _ -> Alcotest.fail "single failing branch is not wrapped in Concurrent");
          match Concurrent.race ~sw [] with
          | Error (Cause.Concurrent []) -> ()
          | _ -> Alcotest.fail "empty race"))

(* ncore-a6g1: a combinator started on an outer switch must stop when its caller's fiber
   is cancelled — workers blocked forever must not keep the caller alive. *)
let test_caller_cancel () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun outer ->
          let forever () : (unit, string) result = Eio.Fiber.await_cancel () in
          let check name start =
            let started = ref false in
            let outcome =
              Eio.Fiber.first
                (fun () ->
                  started := true;
                  ignore (start outer forever);
                  `Finished)
                (fun () ->
                  while not !started do
                    Eio.Fiber.yield ()
                  done;
                  Eio.Fiber.yield ();
                  `Cancelled_caller)
            in
            Alcotest.(check bool)
              (name ^ " returns when its caller is cancelled")
              true (outcome = `Cancelled_caller)
          in
          check "par" (fun sw f -> Ox.Concurrent.par ~sw f f);
          check "all" (fun sw f -> Ox.Concurrent.all ~sw [ f; f ]);
          check "race" (fun sw f -> Ox.Concurrent.race ~sw [ f; f ]);
          check "with_background" (fun sw f -> Ox.Concurrent.with_background ~sw f f)))

let test_par_all () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          Alcotest.(check bool)
            "pair" true
            (Concurrent.par ~sw (fun () -> Ok 1) (fun () -> Ok "two") = Ok (1, "two"));
          Alcotest.(check bool) "empty" true (Concurrent.all ~sw [] = Ok []);
          let live = ref 0 in
          let stopped = ref false in
          let slow () =
            incr live;
            Fun.protect
              (fun () -> Eio.Fiber.await_cancel ())
              ~finally:(fun () ->
                decr live;
                stopped := true)
          in
          let result =
            Concurrent.all ~sw
              [
                slow;
                (fun () ->
                  Eio.Fiber.yield ();
                  Error "no");
              ]
          in
          Alcotest.(check bool) "first typed error" true (result = Error "no");
          Alcotest.(check bool) "cancel awaited" true !stopped;
          Alcotest.(check int) "fiber census ncore-mvvi" 0 !live;
          let started_after_failure = ref false in
          let result =
            Concurrent.all ~sw
              [
                (fun () -> Error "first");
                (fun () ->
                  started_after_failure := true;
                  Ok 2);
              ]
          in
          Alcotest.(check bool)
            "synchronous failure returned unchanged" true (result = Error "first");
          Alcotest.(check bool)
            "fail fast avoids launching later tasks" false !started_after_failure;
          match
            Scope.run (fun sw ->
                Concurrent.par ~sw (fun () -> failwith "defect") (fun () -> Ok 1))
          with
          | Exit.Failure (Cause.Die (Failure _, _)) -> ()
          | _ -> Alcotest.fail "defect was converted"))

let test_background () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let cleaned = ref false in
          let result =
            Concurrent.with_background ~sw
              (fun () ->
                Fun.protect
                  (fun () -> Eio.Fiber.await_cancel ())
                  ~finally:(fun () -> cleaned := true))
              (fun () ->
                Eio.Fiber.yield ();
                Ok 3)
          in
          Alcotest.(check bool) "body first" true (result = Ok 3);
          Alcotest.(check bool) "own stop awaited" true !cleaned;
          let body_stopped = ref false in
          let result =
            Concurrent.with_background ~sw
              (fun () ->
                Eio.Fiber.yield ();
                Error "reader")
              (fun () ->
                Fun.protect
                  (fun () -> Eio.Fiber.await_cancel ())
                  ~finally:(fun () -> body_stopped := true))
          in
          Alcotest.(check bool) "background wins" true (result = Error "reader");
          Alcotest.(check bool) "body awaited" true !body_stopped))

let test_contract () =
  Eio_main.run (fun _ ->
      let expired = Eio.Switch.run Fun.id in
      let never = ref false in
      (match
         Concurrent.race ~sw:expired
           [
             (fun () ->
               never := true;
               Ok 1);
           ]
       with
      | exception Invalid_argument _ -> ()
      | _ -> Alcotest.fail "race accepted closed switch");
      (match Concurrent.all ~sw:expired [] with
      | exception Invalid_argument _ -> ()
      | _ -> Alcotest.fail "all accepted closed switch");
      (match
         Concurrent.with_background ~sw:expired
           (fun () -> Ok ())
           (fun () ->
             never := true;
             Ok 1)
       with
      | exception Invalid_argument _ -> ()
      | _ -> Alcotest.fail "background accepted closed switch");
      Alcotest.(check bool) "closed switch never started work" false !never)

let test_package_contract () =
  let lib = if Sys.file_exists "lib/ox/dune" then "lib/ox" else "../../lib/ox" in
  let read_file path =
    let channel = open_in path in
    Fun.protect
      (fun () -> really_input_string channel (in_channel_length channel))
      ~finally:(fun () -> close_in channel)
  in
  let contains haystack needle =
    let haystack = String.lowercase_ascii haystack in
    let len = String.length needle in
    let rec scan i =
      i + len <= String.length haystack
      && (String.sub haystack i len = needle || scan (i + 1))
    in
    scan 0
  in
  let dune = read_file (Filename.concat lib "dune") in
  Alcotest.(check bool)
    "ncore-kyk3 ox only depends on eio" true
    (contains dune "(libraries eio)" && not (contains dune "effect"));
  let modules =
    [
      "duration";
      "schedule";
      "result";
      "interrupt_id";
      "cause";
      "exit";
      "scope";
      "concurrent";
      "timeout";
      "retry";
      "rate_limiter";
      "select";
      "channel";
      "resource";
      "actor";
      "agent";
      "supervisor";
    ]
  in
  List.iter
    (fun name ->
      let path = Filename.concat lib (name ^ ".mli") in
      Alcotest.(check bool) (name ^ " public mli exists") true (Sys.file_exists path);
      let interface = read_file path in
      Alcotest.(check bool)
        (name ^ " cancellation contract")
        true
        (contains interface "cancell");
      Alcotest.(check bool)
        (name ^ " finalizer contract")
        true
        (contains interface "finaliz"))
    modules

let () =
  Alcotest.run "ox core"
    (Pure.tests @ V1_port.tests @ V1_more.tests @ V1_completion.tests @ Supervised.tests
   @ Actor_tests.tests @ Agent_tests.tests @ Supervisor_tests.tests @ Floor_tests.tests
    @ [
        ( "Core causes ncore-e8jg ncore-k6az ncore-4hth ncore-5dj2 ncore-30fk nobs-xovg \
           ncore-p30f",
          [
            Alcotest.test_case "ncore-e8jg syntax" `Quick test_result_syntax;
            Alcotest.test_case
              "ncore-k6az ncore-4hth ncore-5dj2 ncore-30fk nobs-xovg ncore-p30f cause \
               exit"
              `Quick test_cause_exit;
          ] );
        ( "Scopes ncore-3ry6 ncore-5caq ncore-zpe1",
          [
            Alcotest.test_case "ncore-3ry6 ncore-5caq classification" `Quick
              test_scope_classification;
            Alcotest.test_case "ncore-3ry6 ncore-k6az child defects and deduplication"
              `Quick test_scope_child_defect;
            Alcotest.test_case "ncore-zpe1 resource" `Quick test_resource;
          ] );
        ( "Concurrency ncore-7n2j ncore-7vo9 nfix-yrjy ncore-a6g1 ncore-gpuq ncore-mvvi",
          [
            Alcotest.test_case "ncore-7n2j ncore-acna timeout mock" `Quick
              test_timeout_mock;
            Alcotest.test_case "ncore-7vo9 ncore-mvvi race" `Quick test_race;
            Alcotest.test_case "nfix-yrjy race cause shape" `Quick test_race_cause;
            Alcotest.test_case "ncore-a6g1 ncore-mvvi par all" `Quick test_par_all;
            Alcotest.test_case
              "ncore-a6g1 cancelling the caller cancels par/all/race workers" `Quick
              test_caller_cancel;
            Alcotest.test_case "ncore-gpuq ncore-5caq background" `Quick test_background;
          ] );
        ( "Schedule loops ncore-zda1 ncore-2isd ncore-rzml ncore-acna",
          [
            Alcotest.test_case "ncore-zda1 ncore-2isd ncore-acna mock loops" `Quick
              test_retry_repeat_mock;
            Alcotest.test_case "ncore-rzml ncore-acna sleeping cancellation" `Quick
              test_loop_cancel_mock;
          ] );
        ( "Explicit switches ncore-5zbb",
          [
            Alcotest.test_case "ncore-5zbb rejects closed parent switch" `Quick
              test_contract;
          ] );
        ( "Package contract ncore-kyk3 ncore-161o",
          [
            Alcotest.test_case
              "ncore-kyk3 ncore-161o deps and documented public interfaces" `Quick
              test_package_contract;
          ] );
      ])
