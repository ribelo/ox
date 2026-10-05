(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
let test_run_clock () =
  (* ntest-6du6 *)
  Ox_test.run (fun env _sw ->
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
  Ox_test.run (fun env sw ->
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
      Ox_test.advance env#clock (Ox.Duration.minutes 30);
      Alcotest.(check bool) "sleepers ran before advance returns" true !woke)

let test_fork_run () =
  (* ntest-ckt1 *)
  Ox_test.run (fun env sw ->
      let started, signal_started = Eio.Promise.create () in
      let cleaned = ref false in
      let handle =
        Ox_test.fork_run ~sw (fun child_sw ->
            Eio.Switch.on_release child_sw (fun () -> cleaned := true);
            Eio.Promise.resolve signal_started ();
            Eio.Time.sleep env#clock 5.;
            Ok 42)
      in
      Eio.Promise.await started;
      Eio.Fiber.yield ();
      Ox_test.advance env#clock (Ox.Duration.seconds 5);
      Alcotest.check
        (Ox_test.exit Alcotest.int Alcotest.string)
        "classified exit" (Ox.Exit.Success 42) (Ox_test.await handle);
      Ox_test.assert_no_fibers_left ();
      Alcotest.(check bool) "inner finalizer ran before await" true !cleaned)

let test_structural () =
  (* ntest-190d *)
  let c = Ox_test.cause Alcotest.string in
  Alcotest.(check bool)
    "distinct failures" false
    (Alcotest.equal c (Ox.Cause.Fail "a") (Ox.Cause.Fail "b"));
  Alcotest.(check bool)
    "equal exceptions, different traces" true
    (Alcotest.equal c
       (Ox.Cause.Die (Failure "x", Printexc.get_callstack 1))
       (Ox.Cause.Die (Failure "x", Printexc.get_callstack 5)));
  let e = Ox_test.exit Alcotest.int Alcotest.string in
  Alcotest.(check bool)
    "different exit cases" false
    (Alcotest.equal e (Ox.Exit.Success 1) (Ox.Exit.Failure (Ox.Cause.Fail "e")))

let test_census () =
  (* ntest-8ug3 nlimit-gmur nlimit-9e19 nlimit-i8pu *)
  Ox_test.run (fun _ sw ->
      let p, resolve = Eio.Promise.create () in
      let done_, complete = Eio.Promise.create () in
      let count =
        Ox_test.with_census (fun () ->
            Eio.Fiber.fork ~sw (fun () ->
                Eio.Promise.await p;
                Eio.Promise.resolve complete ());
            Eio.Fiber.yield ())
      in
      Alcotest.(check int) "plain Eio fork detected" 1 count;
      let detected =
        (* ^nlintc-du4v: only the census failure is evidence; cancellation must escape. *)
        match Ox_test.assert_no_fibers_left () with
        | exception (Eio.Cancel.Cancelled _ as cancelled) -> raise cancelled
        | exception _ -> true
        | () -> false
      in
      Alcotest.(check bool) "untracked blocked fiber fails census" true detected;
      Alcotest.(check int)
        "unrelated running root excluded" 0
        (Ox_test.with_census (fun () -> ()));
      Eio.Promise.resolve resolve ();
      Eio.Promise.await done_;
      Ox_test.assert_no_fibers_left ())

let test_lost_events_stay_in_their_run () =
  (* nactor-8z1n: the registry moving onto an Actor made one Leash test heavy enough to
     overrun the event ring; the loss must fail only a census taken in that run. *)
  Ox_test.run (fun _ _ ->
      Eio.Switch.run (fun sw ->
          for _ = 1 to 40_000 do
            Eio.Fiber.fork ~sw (fun () -> ())
          done));
  Ox_test.run (fun _ _ ->
      Alcotest.(check int)
        "a later run counts from its own start" 0
        (Ox_test.with_census (fun () -> ()));
      Ox_test.assert_no_fibers_left ())

let test_census_ring ~(caps : < Ox_caps.Cap.fs_read ; .. >) () =
  (* nlimit-gmur *)
  Ox_test.run (fun _ _ ->
      Alcotest.(check int) "census still counts" 0 (Ox_test.with_census (fun () -> ()));
      let rings =
        Ox_caps.Cap_sys.readdir ~caps (Sys.getcwd ())
        |> Array.to_list
        |> List.filter (fun name -> Filename.check_suffix name ".events")
      in
      Alcotest.(check (list string))
        "no runtime_events ring left in the working directory" [] rings)

let test_flow () =
  (* ntest-knpg *)
  Ox_test.run (fun _ _ ->
      let input, output = Ox_test.flow_pair [ "alpha"; "beta" ] in
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
  Ox_test.run (fun env _ ->
      let fake =
        Ox_test.Process.make
          [
            Ox_test.Process.Exit (`Exited 7);
            Ox_test.Process.Block_until_signal;
            Ox_test.Process.Block_until_signal;
          ]
      in
      let mgr = Ox_test.Process.mgr fake in
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
          let first =
            match Ox_test.Process.spawns fake with
            | head :: _ -> head
            | [] ->
                Alcotest.fail "missing test/run fixture: (Ox_test.Process.spawns fake)"
          in
          Alcotest.(check (list string)) "argv" [ "fake"; "arg" ] first.argv;
          Alcotest.(check string) "executable" "/bin/fake" first.executable;
          Alcotest.(check (list string))
            "environment" [ "KEY=value" ] (Array.to_list first.env);
          Alcotest.(check (option int)) "pgid" (Some 0) first.pgid;
          Alcotest.(check bool) "cwd retained" true (Option.is_some first.cwd);
          Alcotest.(check int) "inherited fd count" 1 (List.length first.fds));
      Alcotest.(check (list int))
        "TERM and switch KILL" [ Sys.sigterm; Sys.sigkill ]
        (Ox_test.Process.signals fake))

module Fake = Ox_test.Process
module Child = Ox_process.Child

let some = function Some pipe -> pipe | None -> Alcotest.fail "expected a piped stream"
let out ?(after = Ox.Duration.zero) data = { Fake.stream = Fake.Stdout; data; after }
let err ?(after = Ox.Duration.zero) data = { Fake.stream = Fake.Stderr; data; after }

(* The same notify-send-shaped child every output test scripts: the real executable path
   the fake manager still has to be handed, and the argv Leash would run. *)
let fake_child
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >)
    (env : Ox_test.env) ~sw fake =
  match
    Child.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:(Fake.mgr fake)
      ~argv:[ "/bin/sh"; "-c"; "notify-send --action done=Done" ]
      ~stdout:Child.Pipe ~stderr:Child.Pipe ~grace:Ox.Duration.zero ~fds:[] ()
  with
  | Ok child -> child
  | Error _ -> Alcotest.fail "unexpected typed spawn failure"

let check_child_exit expected actual =
  let pp = function
    | Child.Exited n -> Printf.sprintf "exit %d" n
    | Child.Signaled n -> Printf.sprintf "signal %d" n
  in
  Alcotest.(check string) "child exit" (pp expected) (pp actual)

let test_process_output
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* ntest-f2rm *)
  Ox_test.run (fun env sw ->
      let fake =
        Fake.make
          [
            Fake.Output
              ([ out "done\n"; err "warn\n"; out "again\n" ], Fake.Exit (`Exited 0));
          ]
      in
      let child = fake_child ~caps env ~sw fake in
      Alcotest.(check string)
        "stdout read through the real Child path" "done\nagain\n"
        (Eio.Flow.read_all (some (Child.stdout child)));
      Alcotest.(check string)
        "stderr read through the real Child path" "warn\n"
        (Eio.Flow.read_all (some (Child.stderr child)));
      check_child_exit (Child.Exited 0) (Child.await child);
      Alcotest.(check (list string))
        "argv recorded as before"
        [ "/bin/sh"; "-c"; "notify-send --action done=Done" ]
        (match Fake.spawns fake with
        | head :: _ -> head
        | [] -> Alcotest.fail "missing test/run fixture: (Fake.spawns fake)")
          .argv)

let test_process_output_delayed
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* ntest-8v5z *)
  Ox_test.run (fun env sw ->
      let fake =
        Fake.make ~clock:env#clock
          [
            Fake.Output
              ([ out ~after:(Ox.Duration.minutes 30) "done\n" ], Fake.Block_until_signal);
          ]
      in
      let child = fake_child ~caps env ~sw fake in
      let source = some (Child.stdout child) in
      let buffer = Cstruct.create 5 in
      let reading =
        Eio.Fiber.fork_promise ~sw (fun () -> Eio.Flow.single_read source buffer)
      in
      Ox_test.advance env#clock (Ox.Duration.seconds 1);
      Alcotest.(check bool)
        "no byte before the delay" false
        (Eio.Promise.is_resolved reading);
      Ox_test.advance env#clock (Ox.Duration.minutes 30);
      (match Eio.Promise.await reading with
      | Ok read -> Alcotest.(check int) "chunk after the delay" 5 read
      | Error ex -> Alcotest.failf "reader failed: %s" (Printexc.to_string ex));
      Alcotest.(check string) "chunk bytes" "done\n" (Cstruct.to_string buffer);
      check_child_exit (Child.Signaled Sys.sigterm) (Child.stop child);
      Alcotest.(check string)
        "EOF when the child is stopped" "" (Eio.Flow.read_all source))

let test_process_output_stopped
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* ntest-8v5z *)
  Ox_test.run (fun env sw ->
      let fake =
        Fake.make ~clock:env#clock
          [
            Fake.Output
              ([ out ~after:(Ox.Duration.hours 1) "done\n" ], Fake.Block_until_signal);
          ]
      in
      let child = fake_child ~caps env ~sw fake in
      let source = some (Child.stdout child) in
      check_child_exit (Child.Signaled Sys.sigterm) (Child.stop child);
      Alcotest.(check string) "EOF, not the pending chunk" "" (Eio.Flow.read_all source);
      Alcotest.(check (list int)) "TERM only" [ Sys.sigterm ] (Fake.signals fake);
      Alcotest.(check bool)
        "clock never advanced" true
        (Float.equal 0. (Eio.Time.now env#clock)))

let test_package () =
  (* ntest-n53y *)
  Alcotest.(check bool)
    "ox_test functions link with ox and eio" true
    (Alcotest.equal (Ox_test.cause Alcotest.int) (Ox.Cause.Fail 1) (Ox.Cause.Fail 1));
  Alcotest.(check int)
    "runtime_events and eio.runtime_events linked" 0
    (Ox_test.with_census (fun () -> ()))

let () =
  Alcotest.run "ox_test"
    [
      ("ntest-6du6", [ Alcotest.test_case "mock standard env" `Quick test_run_clock ]);
      ("ntest-4227", [ Alcotest.test_case "virtual clock advance" `Quick test_advance ]);
      ("ntest-ckt1", [ Alcotest.test_case "fork and await" `Quick test_fork_run ]);
      ( "ntest-190d",
        [ Alcotest.test_case "structural Exit and Cause" `Quick test_structural ] );
      ( "ntest-8ug3",
        [
          Alcotest.test_case "detect actual leaked fiber" `Quick test_census;
          Alcotest.test_case "census ring outside the cwd" `Quick (fun () ->
              test_census_ring ~caps:(Ox_test.powerbox ()) ());
          Alcotest.test_case "nactor-8z1n lost events stay in their run" `Quick
            test_lost_events_stay_in_their_run;
        ] );
      ("ntest-knpg", [ Alcotest.test_case "scripted source sink" `Quick test_flow ]);
      ( "ntest-0b6v",
        [ Alcotest.test_case "process spawn fds and signals" `Quick test_process ] );
      ( "ntest-f2rm",
        [
          Alcotest.test_case "scripted child output through Child" `Quick (fun () ->
              test_process_output ~caps:(Ox_test.powerbox ()) ());
        ] );
      ( "ntest-8v5z",
        [
          Alcotest.test_case "delayed chunk on the mock clock" `Quick (fun () ->
              test_process_output_delayed ~caps:(Ox_test.powerbox ()) ());
          Alcotest.test_case "stopped before its delayed chunk" `Quick (fun () ->
              test_process_output_stopped ~caps:(Ox_test.powerbox ()) ());
        ] );
      ("ntest-n53y", [ Alcotest.test_case "package links" `Quick test_package ]);
    ]
