let test_run_clock () =
  (* ntest-6du6 *)
  Eta_test.run (fun env _sw ->
      Alcotest.(check bool)
        "mock time starts at zero" true
        (Float.equal 0. (Eio.Time.now env#clock));
      Alcotest.(check bool)
        "real fs exists" true
        (Eio.Path.is_directory Eio.Path.(env#fs / "/"));
      Alcotest.(check bool) "backend remains real" true (env#backend_id <> "mock");
      Alcotest.(check bool)
        "mock monotonic clock has no events" false
        (Eio_mock.Clock.Mono.try_advance env#mono_clock))

let test_advance () =
  (* ntest-4227 *)
  Eta_test.run (fun env sw ->
      let woke = ref false in
      let sleeping = ref false in
      let started, signal_started = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Promise.resolve signal_started ();
          sleeping := true;
          Eio.Time.sleep env#clock 1800.;
          woke := true);
      Eio.Promise.await started;
      Eio.Fiber.yield ();
      Alcotest.(check bool) "child entered sleep" true !sleeping;
      Eta_test.advance env#clock (Eta.Duration.minutes 30);
      Alcotest.(check bool) "sleepers ran before advance returns" true !woke)

let test_fork_run () =
  (* ntest-ckt1 *)
  Eta_test.run (fun env sw ->
      let started, signal_started = Eio.Promise.create () in
      let cleaned = ref false in
      let handle =
        Eta_test.fork_run ~sw (fun child_sw ->
            Eio.Switch.on_release child_sw (fun () -> cleaned := true);
            Eio.Promise.resolve signal_started ();
            Eio.Time.sleep env#clock 5.;
            Ok 42)
      in
      Eio.Promise.await started;
      Eio.Fiber.yield ();
      Eta_test.advance env#clock (Eta.Duration.seconds 5);
      Alcotest.check
        (Eta_test.exit Alcotest.int Alcotest.string)
        "classified exit" (Eta.Exit.Success 42) (Eta_test.await handle);
      Eta_test.assert_no_fibers_left ();
      Alcotest.(check bool) "inner finalizer ran before await" true !cleaned)

let test_structural () =
  (* ntest-190d *)
  let c = Eta_test.cause Alcotest.string in
  Alcotest.(check bool)
    "distinct failures" false
    (Alcotest.equal c (Eta.Cause.Fail "a") (Eta.Cause.Fail "b"));
  Alcotest.(check bool)
    "equal exceptions, different traces" true
    (Alcotest.equal c
       (Eta.Cause.Die (Failure "x", Printexc.get_callstack 1))
       (Eta.Cause.Die (Failure "x", Printexc.get_callstack 5)));
  let e = Eta_test.exit Alcotest.int Alcotest.string in
  Alcotest.(check bool)
    "different exit cases" false
    (Alcotest.equal e (Eta.Exit.Success 1) (Eta.Exit.Failure (Eta.Cause.Fail "e")))

let test_census () =
  (* ntest-8ug3 nlimit-gmur nlimit-9e19 nlimit-i8pu *)
  Eta_test.run (fun _ sw ->
      let p, resolve = Eio.Promise.create () in
      let done_, complete = Eio.Promise.create () in
      let count =
        Eta_test.with_census (fun () ->
            Eio.Fiber.fork ~sw (fun () ->
                Eio.Promise.await p;
                Eio.Promise.resolve complete ());
            Eio.Fiber.yield ())
      in
      Alcotest.(check int) "plain Eio fork detected" 1 count;
      let detected =
        match Eta_test.assert_no_fibers_left () with exception _ -> true | () -> false
      in
      Alcotest.(check bool) "untracked blocked fiber fails census" true detected;
      Alcotest.(check int)
        "unrelated running root excluded" 0
        (Eta_test.with_census (fun () -> ()));
      Eio.Promise.resolve resolve ();
      Eio.Promise.await done_;
      Eta_test.assert_no_fibers_left ())

let test_flow () =
  (* ntest-knpg *)
  Eta_test.run (fun _ _ ->
      let input, output = Eta_test.flow_pair [ "alpha"; "beta" ] in
      let buf = Cstruct.create 16 in
      Alcotest.(check int) "first read" 5 (Eio.Flow.single_read input buf);
      Alcotest.(check string)
        "first bytes" "alpha"
        (Cstruct.to_string (Cstruct.sub buf 0 5));
      Alcotest.(check int) "second read" 4 (Eio.Flow.single_read input buf);
      Alcotest.(check bool)
        "script ends at EOF" true
        (match Eio.Flow.single_read input buf with
        | exception End_of_file -> true
        | _ -> false);
      Eio.Flow.copy_string "response" output)

let test_process () =
  (* ntest-0b6v *)
  Eta_test.run (fun env _ ->
      let fake =
        Eta_test.Process.make
          [
            Eta_test.Process.Exit (`Exited 7);
            Eta_test.Process.Block_until_signal;
            Eta_test.Process.Block_until_signal;
          ]
      in
      let mgr = Eta_test.Process.mgr fake in
      Eio.Switch.run (fun sw ->
          let inherited = [ (4, Eio_unix.Fd.stdin, `Preserve_blocking) ] in
          let proc =
            Eio_unix.Process.spawn_unix ~sw mgr ~cwd:env#cwd ~pgid:0 ~fds:inherited
              ~env:[| "KEY=value" |] ~executable:"/bin/fake" [ "fake"; "arg" ]
          in
          Alcotest.(check int)
            "scripted exit" 7
            (match Eio.Process.await proc with `Exited n -> n | _ -> -1);
          let child = Eio.Process.spawn ~sw mgr [ "daemon" ] in
          Eio.Process.signal child Sys.sigterm;
          Alcotest.(check int)
            "SIGTERM wakes child" Sys.sigterm
            (match Eio.Process.await child with `Signaled n -> n | _ -> -1);
          let _pending = Eio.Process.spawn ~sw mgr [ "cleanup" ] in
          let first = List.hd (Eta_test.Process.spawns fake) in
          Alcotest.(check (list string)) "argv" [ "fake"; "arg" ] first.argv;
          Alcotest.(check string) "executable" "/bin/fake" first.executable;
          Alcotest.(check (list string))
            "environment" [ "KEY=value" ] (Array.to_list first.env);
          Alcotest.(check (option int)) "pgid" (Some 0) first.pgid;
          Alcotest.(check bool) "cwd retained" true (Option.is_some first.cwd);
          Alcotest.(check int) "inherited fd count" 1 (List.length first.fds));
      Alcotest.(check (list int))
        "TERM and switch KILL" [ Sys.sigterm; Sys.sigkill ]
        (Eta_test.Process.signals fake))

let test_package () =
  (* ntest-n53y *)
  Alcotest.(check bool)
    "eta_test functions link with eta and eio" true
    (Alcotest.equal (Eta_test.cause Alcotest.int) (Eta.Cause.Fail 1) (Eta.Cause.Fail 1));
  Alcotest.(check int)
    "runtime_events and eio.runtime_events linked" 0
    (Eta_test.with_census (fun () -> ()))

let () =
  Alcotest.run "eta_test"
    [
      ("ntest-6du6", [ Alcotest.test_case "mock standard env" `Quick test_run_clock ]);
      ("ntest-4227", [ Alcotest.test_case "virtual clock advance" `Quick test_advance ]);
      ("ntest-ckt1", [ Alcotest.test_case "fork and await" `Quick test_fork_run ]);
      ( "ntest-190d",
        [ Alcotest.test_case "structural Exit and Cause" `Quick test_structural ] );
      ( "ntest-8ug3",
        [ Alcotest.test_case "detect actual leaked fiber" `Quick test_census ] );
      ("ntest-knpg", [ Alcotest.test_case "scripted source sink" `Quick test_flow ]);
      ( "ntest-0b6v",
        [ Alcotest.test_case "process spawn fds and signals" `Quick test_process ] );
      ("ntest-n53y", [ Alcotest.test_case "package links" `Quick test_package ]);
    ]
