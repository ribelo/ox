module C = Ox_process.Child
module S = Ox_process.Supervised

let check_exit expected actual =
  let pp = function
    | C.Exited n -> Printf.sprintf "exit %d" n
    | C.Signaled n -> Printf.sprintf "signal %d" n
  in
  Alcotest.(check string) "child exit" (pp expected) (pp actual)

let ok = function Ok v -> v | Error _ -> Alcotest.fail "unexpected typed spawn failure"
let some = function Some x -> x | None -> Alcotest.fail "expected pipe"

let fd flow =
  match Eio_unix.Resource.fd_opt flow with
  | Some x -> x
  | None -> Alcotest.fail "expected unix fd"

let with_script ~(caps : < Ox_caps.Cap.tmp ; Ox_caps.Cap.fs_write ; .. >) body fn =
  let dir = Ox_caps.Cap_stdlib.Filename.temp_dir ~caps "ox-process-" "" in
  let path = Filename.concat dir "child.sh" in
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists (path ^ ".ready") then
        Ox_caps.Cap_sys.remove ~caps (path ^ ".ready");
      Ox_caps.Cap_sys.remove ~caps path;
      Ox_caps.Cap_unix.rmdir ~caps dir)
    (fun () ->
      let oc = Ox_caps.Cap_stdlib.open_out ~caps path in
      output_string oc ("#!/bin/sh\n" ^ body ^ "\n");
      close_out oc;
      Ox_caps.Cap_unix.chmod ~caps path 0o700;
      fn path)

let test_invalid
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* nproc-7bkl *)
  Ox_test.run (fun env sw ->
      let fake = Ox_test.Process.make [] in
      let spawn fds =
        C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:(Ox_test.Process.mgr fake)
          ~argv:[ "/bin/never" ] ~grace:Ox.Duration.zero ~fds ()
      in
      Alcotest.(check bool)
        "negative rejected" true
        (match spawn [ (-1, Eio_unix.Fd.stdin) ] with
        | Error (`Invalid_fd -1) -> true
        | _ -> false);
      Alcotest.(check bool)
        "standard fd rejected" true
        (match spawn [ (2, Eio_unix.Fd.stdin) ] with
        | Error (`Invalid_fd 2) -> true
        | _ -> false);
      Alcotest.(check bool)
        "duplicate rejected" true
        (match spawn [ (3, Eio_unix.Fd.stdin); (3, Eio_unix.Fd.stdout) ] with
        | Error (`Duplicate_fd 3) -> true
        | _ -> false);
      Alcotest.(check int) "no spawn" 0 (List.length (Ox_test.Process.spawns fake)))

let test_fake_retirement
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* nproc-e5zc nproc-71a7 nproc-bqik *)
  Ox_test.run (fun env sw ->
      let fake = Ox_test.Process.make [ Ox_test.Process.Block_until_signal ] in
      let child =
        ok
          (C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:(Ox_test.Process.mgr fake)
             ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      check_exit (C.Signaled Sys.sigterm) (C.stop child);
      check_exit (C.Signaled Sys.sigterm) (C.stop child);
      check_exit (C.Signaled Sys.sigterm) (C.await child);
      Alcotest.(check (list int))
        "TERM only; Eio backstop inert" [ Sys.sigterm ]
        (Ox_test.Process.signals fake))

let test_supervision
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* nproc-cyeq nproc-msz4 nproc-pnnm nproc-ypzm *)
  Ox_test.run (fun env sw ->
      let fake =
        Ox_test.Process.make
          [ Ox_test.Process.Exit (`Exited 3); Ox_test.Process.Exit (`Exited 0) ]
      in
      let schedule =
        Ox.Schedule.modify_delay
          (fun _ _ -> Ox.Duration.seconds 10)
          (Ox.Schedule.recurs 1)
      in
      let supervisor =
        S.start ~sw ~clock:env#mono_clock ~schedule ~spawn:(fun ~sw ->
            C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:(Ox_test.Process.mgr fake)
              ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      let events = S.events supervisor in
      (match Eio.Stream.take events with
      | S.Started 1 -> ()
      | _ -> Alcotest.fail "start 1");
      (match Eio.Stream.take events with
      | S.Exited (1, C.Exited 3) -> ()
      | _ -> Alcotest.fail "exit 1");
      Alcotest.(check int)
        "not restarted before delay" 1
        (List.length (Ox_test.Process.spawns fake));
      Eio_mock.Clock.Mono.set_time env#mono_clock (Mtime.of_uint64_ns 10_000_000_000L);
      Eio.Fiber.yield ();
      (match Eio.Stream.take events with
      | S.Started 2 -> ()
      | _ -> Alcotest.fail "start 2");
      (match Eio.Stream.take events with
      | S.Exited (2, C.Exited 0) -> ()
      | _ -> Alcotest.fail "exit 2");
      (match Eio.Stream.take events with
      | S.Gave_up (Ox.Cause.Fail (`Schedule_exhausted (C.Exited 0))) -> ()
      | _ -> Alcotest.fail "exhausted");
      Alcotest.(check int) "generation" 2 (S.generation supervisor);
      S.stop supervisor;
      (match Eio.Stream.take events with
      | S.Stopped -> ()
      | _ -> Alcotest.fail "nlimit-a407: Gave_up must precede Stopped");
      Alcotest.(check (option bool))
        "terminal last" None
        (Option.map
           (function S.Stopped -> true | _ -> false)
           (Eio.Stream.take_nonblocking events));
      Ox_test.assert_no_fibers_left ())

let test_stop
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* nproc-svva nproc-pnnm *)
  Ox_test.run (fun env sw ->
      let fake = Ox_test.Process.make [ Ox_test.Process.Block_until_signal ] in
      let s =
        S.start ~sw ~clock:env#mono_clock ~schedule:Ox.Schedule.forever ~spawn:(fun ~sw ->
            C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:(Ox_test.Process.mgr fake)
              ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      (match Eio.Stream.take (S.events s) with
      | S.Started 1 -> ()
      | _ -> Alcotest.fail "started");
      S.stop s;
      S.stop s;
      (match Eio.Stream.take (S.events s) with
      | S.Stopped -> ()
      | _ -> Alcotest.fail "nlimit-a407: stop must end stream");
      Alcotest.(check (option bool))
        "no duplicate Stopped" None
        (Option.map
           (function S.Stopped -> true | _ -> false)
           (Eio.Stream.take_nonblocking (S.events s)));
      Alcotest.(check int) "single generation" 1 (S.generation s);
      Alcotest.(check (list int))
        "TERM on shutdown" [ Sys.sigterm ]
        (Ox_test.Process.signals fake);
      Alcotest.(check int) "no respawn" 1 (List.length (Ox_test.Process.spawns fake)))

let test_spawn_failure () =
  (* nproc-pnnm nproc-msz4 *)
  Ox_test.run (fun env sw ->
      let s =
        S.start ~sw ~clock:env#mono_clock ~schedule:Ox.Schedule.forever
          ~spawn:(fun ~sw:_ -> Error `Unavailable)
      in
      (match Eio.Stream.take (S.events s) with
      | S.Gave_up (Ox.Cause.Fail (`Spawn `Unavailable)) -> ()
      | _ -> Alcotest.fail "typed spawn failure");
      Alcotest.(check int) "no successful spawn" 0 (S.generation s);
      S.stop s;
      match Eio.Stream.take (S.events s) with
      | S.Stopped -> ()
      | _ -> Alcotest.fail "nlimit-a407: typed Gave_up then Stopped")

let test_overflow
    ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >) () =
  (* nproc-pnnm nproc-msz4 *)
  Ox_test.run (fun env sw ->
      let fake =
        Ox_test.Process.make (List.init 33 (fun _ -> Ox_test.Process.Exit (`Exited 0)))
      in
      let s =
        S.start ~sw ~clock:env#mono_clock ~schedule:(Ox.Schedule.recurs 32)
          ~spawn:(fun ~sw ->
            C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:(Ox_test.Process.mgr fake)
              ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      let rec settle attempts =
        if S.generation s < 33 && attempts > 0 then (
          Eio.Fiber.yield ();
          settle (attempts - 1))
      in
      settle 200;
      Alcotest.(check int) "all spawns" 33 (S.generation s);
      S.stop s;
      Alcotest.(check int) "bounded stream" 32 (Eio.Stream.length (S.events s));
      Alcotest.(check bool) "old events dropped" true (S.dropped s > 0))

let test_fd_and_output
    ~(caps :
       < Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; Ox_caps.Cap.tmp
       ; .. >) () =
  (* nproc-1x05 nproc-giyu nproc-bqik *)
  with_script ~caps
    "read line <&3; printf 'reply:%s\n' $line >&4; echo stdout; echo stderr >&2; exit 3"
    (fun script ->
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let read3, write3 = Eio_unix.pipe sw in
              let read4, write4 = Eio_unix.pipe sw in
              let child =
                ok
                  (C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                     ~argv:[ script ] ~grace:(Ox.Duration.ms 40) ~stdout:C.Pipe
                     ~stderr:C.Pipe
                     ~fds:[ (3, fd read3); (4, fd write4) ]
                     ())
              in
              (* daily-c4cl: the child's OS pid is reported. *)
              Alcotest.(check bool)
                "pid is a live process" true
                (let pid = C.pid child in
                 pid > 0 && Sys.file_exists (Printf.sprintf "/proc/%d" pid));
              Eio.Resource.close read3;
              Eio.Resource.close write4;
              Eio.Flow.copy_string "hello\n" write3;
              Eio.Resource.close write3;
              Alcotest.(check string)
                "fd 4" "reply:hello\n"
                (Eio.Buf_read.(parse_exn take_all ~max_size:1_048_576) read4);
              Alcotest.(check string)
                "stdout" "stdout\n"
                (Eio.Buf_read.(parse_exn take_all ~max_size:1_048_576)
                   (some (C.stdout child)));
              Alcotest.(check string)
                "stderr" "stderr\n"
                (Eio.Buf_read.(parse_exn take_all ~max_size:1_048_576)
                   (some (C.stderr child)));
              check_exit (C.Exited 3) (C.await child);
              check_exit (C.Exited 3) (C.stop child))))

let test_mapped_fds_blocking
    ~(caps :
       < Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; Ox_caps.Cap.tmp
       ; .. >) () =
  (* nproc-1x05: the child sees blocking descriptors even though Eio's pipes are
     non-blocking in the parent *)
  with_script ~caps
    "for n in 1 3 4; do awk '/^flags/ {print $2}' /proc/self/fdinfo/$n >&2; done"
    (fun script ->
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let read3, _write3 = Eio_unix.pipe sw in
              let _read4, write4 = Eio_unix.pipe sw in
              let child =
                ok
                  (C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                     ~argv:[ script ] ~grace:(Ox.Duration.ms 40) ~stdout:C.Pipe
                     ~stderr:C.Pipe
                     ~fds:[ (3, fd read3); (4, fd write4) ]
                     ())
              in
              let flags =
                Eio.Buf_read.(parse_exn take_all ~max_size:1_048_576)
                  (some (C.stderr child))
                |> String.split_on_char '\n'
                |> List.filter (( <> ) "")
              in
              Alcotest.(check int) "three descriptors reported" 3 (List.length flags);
              List.iter
                (fun f ->
                  let v = int_of_string ("0o" ^ f) in
                  Alcotest.(check bool) ("O_NONBLOCK clear: " ^ f) true (v land 0o4000 = 0))
                flags;
              ignore (C.stop child))))

let test_retired_output_eof
    ~(caps :
       < Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; Ox_caps.Cap.tmp
       ; .. >) () =
  (* nlimit-nzur *)
  with_script ~caps "printf output; printf error >&2" (fun script ->
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let child =
                ok
                  (C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                     ~argv:[ script ] ~grace:(Ox.Duration.ms 30) ~stdout:C.Pipe
                     ~stderr:C.Pipe ~fds:[] ())
              in
              check_exit (C.Exited 0) (C.await child);
              check_exit (C.Exited 0) (C.stop child);
              Alcotest.(check string)
                "stdout buffered through retirement then EOF" "output"
                (Eio.Buf_read.(parse_exn take_all ~max_size:1_048_576)
                   (some (C.stdout child)));
              Alcotest.(check string)
                "stderr buffered through retirement then EOF" "error"
                (Eio.Buf_read.(parse_exn take_all ~max_size:1_048_576)
                   (some (C.stderr child))))))

let wait_ready clock marker =
  match
    Ox.Timeout.timeout_mono ~clock (Ox.Duration.seconds 1) (fun () ->
        while not (Sys.file_exists marker) do
          Eio.Time.Mono.sleep clock 0.001
        done;
        Ok ())
  with
  | Ok () -> ()
  | Error `Timeout -> Alcotest.fail "child readiness timed out"

let test_escalation
    ~(caps :
       < Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; Ox_caps.Cap.tmp
       ; .. >) grace () =
  (* nproc-xmat nproc-e5zc nproc-ypzm *)
  with_script ~caps {|trap '' TERM; printf ready > "$1"; exec sleep 30|} (fun script ->
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let child =
                ok
                  (C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                     ~argv:[ script; script ^ ".ready" ]
                     ~grace ~fds:[] ())
              in
              wait_ready env#mono_clock (script ^ ".ready");
              check_exit (C.Signaled Sys.sigkill) (C.stop child);
              check_exit (C.Signaled Sys.sigkill) (C.await child))))

let test_supervisor_real_stop
    ~(caps :
       < Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; Ox_caps.Cap.tmp
       ; .. >) () =
  (* nproc-svva nproc-e5zc nproc-xmat *)
  with_script ~caps {|trap '' TERM; printf ready > "$1"; exec sleep 30|} (fun script ->
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let spawned = ref None in
              let supervisor =
                S.start ~sw ~clock:env#mono_clock ~schedule:Ox.Schedule.forever
                  ~spawn:(fun ~sw ->
                    let result =
                      C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                        ~argv:[ script; script ^ ".ready" ]
                        ~grace:(Ox.Duration.ms 20) ~fds:[] ()
                    in
                    (match result with
                    | Ok child -> spawned := Some child
                    | Error _ -> ());
                    result)
              in
              (match Eio.Stream.take (S.events supervisor) with
              | S.Started 1 -> ()
              | _ -> Alcotest.fail "supervisor did not start");
              wait_ready env#mono_clock (script ^ ".ready");
              S.stop supervisor;
              check_exit (C.Signaled Sys.sigkill) (C.await (some !spawned));
              Alcotest.(check int)
                "no replacement after shutdown" 1 (S.generation supervisor))))

let test_cancel
    ~(caps :
       < Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; Ox_caps.Cap.tmp
       ; .. >) () =
  (* nproc-71a7 nproc-e5zc *)
  with_script ~caps
    {|trap 'kill $worker; wait $worker; exit 0' TERM; sleep 30 & worker=$!; printf ready > "$1"; wait "$worker"|}
    (fun script ->
      Eio_main.run (fun env ->
          Eio.Switch.run (fun outer ->
              let ready, ready_u = Eio.Promise.create () in
              let scope =
                Eio.Fiber.fork_promise ~sw:outer (fun () ->
                    Ox.Scope.run (fun sw ->
                        let child =
                          ok
                            (C.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                               ~argv:[ script; script ^ ".ready" ]
                               ~grace:(Ox.Duration.ms 40) ~fds:[] ())
                        in
                        wait_ready env#mono_clock (script ^ ".ready");
                        Eio.Promise.resolve ready_u (sw, child);
                        let never, _ = Eio.Promise.create () in
                        Eio.Promise.await never;
                        Ok ()))
              in
              let sw, child = Eio.Promise.await ready in
              Eio.Switch.fail sw (Failure "owner cancelled");
              (match Eio.Promise.await_exn scope with
              | Ox.Exit.Failure _ -> ()
              | _ -> Alcotest.fail "cancel expected");
              check_exit (C.Exited 0) (C.await child);
              check_exit (C.Exited 0) (C.stop child))))

let () =
  let caps =
    (Ox_test.powerbox ()
      :> < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; Ox_caps.Cap.tmp >)
  in
  Alcotest.run "ox_process"
    [
      ( "nproc-7bkl",
        [ Alcotest.test_case "invalid fd mappings" `Quick (test_invalid ~caps) ] );
      ( "nproc-e5zc nproc-71a7 nproc-bqik",
        [ Alcotest.test_case "fake retirement" `Quick (test_fake_retirement ~caps) ] );
      ( "nproc-cyeq nproc-msz4 nproc-pnnm nproc-ypzm",
        [ Alcotest.test_case "scheduled restart" `Quick (test_supervision ~caps) ] );
      ( "nproc-svva nproc-pnnm",
        [ Alcotest.test_case "stop never respawns" `Quick (test_stop ~caps) ] );
      ( "nproc-pnnm nproc-msz4",
        [
          Alcotest.test_case "typed spawn failure" `Quick test_spawn_failure;
          Alcotest.test_case "bounded event overflow" `Quick (test_overflow ~caps);
        ] );
      ( "nproc-1x05 nproc-giyu nproc-bqik nlimit-nzur",
        [
          Alcotest.test_case "real fd pipes and output" `Quick (test_fd_and_output ~caps);
          Alcotest.test_case "nproc-1x05 mapped fds are blocking in the child" `Quick
            (test_mapped_fds_blocking ~caps);
          Alcotest.test_case "retired output reaches EOF" `Quick
            (test_retired_output_eof ~caps);
        ] );
      ( "nproc-xmat nproc-e5zc nproc-ypzm",
        [
          Alcotest.test_case "real escalation" `Quick
            ((test_escalation ~caps) (Ox.Duration.ms 30));
          Alcotest.test_case "zero grace immediate kill" `Quick
            ((test_escalation ~caps) Ox.Duration.zero);
        ] );
      ( "nproc-svva nproc-e5zc nproc-xmat",
        [
          Alcotest.test_case "real supervisor shutdown" `Quick
            (test_supervisor_real_stop ~caps);
        ] );
      ( "nproc-71a7 nproc-e5zc",
        [ Alcotest.test_case "cancel reaps" `Quick (test_cancel ~caps) ] );
    ]
