module C = Ox_process.Child
module S = Ox_process.Supervised

(* safe-p9cw safe-8peq safe-5a9k: never adjust the host clock. The wall
   clock is independent of the native monotonic clock driving the budget. *)
let process_clock (env : Ox_test.env) = env#mono_clock

let settle () =
  for _ = 1 to 16 do
    Eio.Fiber.yield ()
  done

let ok = function Ok x -> x | Error _ -> Alcotest.fail "spawn failed"
let ns n = Mtime.of_uint64_ns n

let mono env n =
  Eio_mock.Clock.Mono.set_time env#mono_clock (ns n);
  settle ()

let wall env t =
  Eio_mock.Clock.set_time env#clock t;
  settle ()

(* This public Eio process provider ignores TERM, acknowledges KILL, and
   gates its private-switch release. Thus timeout, reap and physical cleanup
   are separate observations, rather than merely a returned exit value. *)
type retirement = {
  finished : Eio.Process.exit_status Eio.Promise.t;
  finish : Eio.Process.exit_status Eio.Promise.u;
  release : unit Eio.Promise.t;
  release_u : unit Eio.Promise.u;
  mutable signals : int list;
  mutable reaped : bool;
  mutable finalizing : bool;
  mutable finalized : bool;
}

let retirement () =
  let finished, finish = Eio.Promise.create () in
  let release, release_u = Eio.Promise.create () in
  {
    finished;
    finish;
    release;
    release_u;
    signals = [];
    reaped = false;
    finalizing = false;
    finalized = false;
  }

module Process = struct
  type t = retirement
  type tag = [ `Generic | `Unix ]

  let pid _ = 4242

  let await t =
    let status = Eio.Promise.await t.finished in
    t.reaped <- true;
    status

  let signal t signum =
    if not (Eio.Promise.is_resolved t.finished) then (
      t.signals <- t.signals @ [ signum ];
      if signum = Sys.sigkill then
        ignore (Eio.Promise.try_resolve t.finish (`Signaled signum)))
end

module Manager = Eio_unix.Process.Make_mgr (struct
  type t = retirement

  let spawn_unix t ~sw ?cwd:_ ?pgid:_ ?uid:_ ?gid:_ ?login_tty:_ ~env:_ ~fds:_
      ~executable:_ _ =
    Eio.Switch.on_release sw (fun () ->
        t.finalizing <- true;
        Eio.Promise.await t.release;
        t.finalized <- true);
    Eio.Resource.T (t, Eio.Process.Pi.process (module Process))
end)

let mgr t = Eio.Resource.T (t, Eio_unix.Process.Pi.mgr_unix (module Manager))
let release t = ignore (Eio.Promise.try_resolve t.release_u ())

let spawn ~caps env ~sw t =
  C.spawn ~caps ~sw ~clock:(process_clock env) ~mgr:(mgr t) ~env:[||] ~argv:[ "/bin/sh" ]
    ~grace:(Ox.Duration.ms 100) ~fds:[] ()
  |> ok

let signals expected t = Alcotest.(check (list int)) "TERM/grace/KILL" expected t.signals

let rescue env t =
  Eio.Cancel.protect (fun () ->
      Process.signal t Sys.sigkill;
      release t;
      wall env 1_000_000.;
      mono env 9_000_000_000_000_000_000L)

let with_retirement fn =
  Ox_test.run (fun env sw ->
      let t = retirement () in
      Fun.protect ~finally:(fun () -> rescue env t) (fun () -> fn env sw t))

let fork_exit ~sw fn = Eio.Fiber.fork_promise ~sw (fun () -> Ox.Scope.run fn)

let assert_interrupt promise =
  match Eio.Promise.await_exn promise with
  | Ox.Exit.Failure (Ox.Cause.Interrupt _) -> ()
  | _ -> Alcotest.fail "cancellation must remain Interrupt, not timeout or Die"

let stopped supervisor =
  match Eio.Stream.take_nonblocking (S.events supervisor) with
  | Some S.Stopped ->
      Alcotest.(check int)
        "Stopped is last and unique" 0
        (Eio.Stream.length (S.events supervisor))
  | Some (S.Gave_up _) -> Alcotest.fail "cancellation was misclassified as Gave_up"
  | _ -> Alcotest.fail "missing terminal Stopped"

let child_grace ~caps jump () =
  with_retirement (fun env sw t ->
      release t;
      let child = spawn ~caps env ~sw t in
      let result = Eio.Fiber.fork_promise ~sw (fun () -> C.stop child) in
      settle ();
      signals [ Sys.sigterm ] t;
      mono env 50_000_000L;
      wall env jump;
      signals [ Sys.sigterm ] t;
      Alcotest.(check bool)
        "stop still waiting before native grace" false
        (Eio.Promise.is_resolved result);
      mono env 100_000_000L;
      signals [ Sys.sigterm; Sys.sigkill ] t;
      (match Eio.Promise.await_exn result with
      | C.Signaled n when n = Sys.sigkill -> ()
      | _ -> Alcotest.fail "grace must escalate to KILL");
      Alcotest.(check bool) "await physically reaped" true t.reaped;
      Alcotest.(check bool) "private switch joined before stop" true t.finalized;
      match C.stop child with
      | C.Signaled n when n = Sys.sigkill -> ()
      | _ -> assert false)

let child_cancelled_stop ~caps () =
  with_retirement (fun env sw t ->
      let child = spawn ~caps env ~sw t in
      let context, context_u = Eio.Promise.create () in
      let result =
        fork_exit ~sw (fun _scope_sw ->
            Eio.Cancel.sub (fun ctx ->
                Eio.Promise.resolve context_u ctx;
                ignore (C.stop child);
                Eio.Cancel.check ctx;
                Ok ()))
      in
      Eio.Cancel.cancel (Eio.Promise.await context) Exit;
      settle ();
      mono env 100_000_000L;
      signals [ Sys.sigterm; Sys.sigkill ] t;
      Alcotest.(check bool) "reaped" true t.reaped;
      Alcotest.(check bool) "release entered" true t.finalizing;
      Alcotest.(check bool)
        "cancelled stop still joins physical release" false
        (Eio.Promise.is_resolved result);
      release t;
      assert_interrupt result;
      Alcotest.(check bool) "release joined" true t.finalized)

let supervised_backoff ~caps jump () =
  Ox_test.run (fun env sw ->
      let fake =
        Ox_test.Process.make
          [ Ox_test.Process.Exit (`Exited 1); Ox_test.Process.Block_until_signal ]
      in
      let schedule =
        Ox.Schedule.modify_delay (fun _ _ -> Ox.Duration.ms 100) (Ox.Schedule.recurs 1)
      in
      let supervisor =
        S.start ~sw ~clock:(process_clock env) ~schedule ~spawn:(fun ~sw ->
            C.spawn ~caps ~sw ~clock:(process_clock env) ~mgr:(Ox_test.Process.mgr fake)
              ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      Fun.protect
        ~finally:(fun () ->
          wall env 1_000_000.;
          mono env 9_000_000_000_000_000_000L;
          S.stop supervisor)
        (fun () ->
          (match Eio.Stream.take (S.events supervisor) with
          | S.Started 1 -> ()
          | _ -> assert false);
          (match Eio.Stream.take (S.events supervisor) with
          | S.Exited (1, _) -> ()
          | _ -> assert false);
          settle ();
          mono env 50_000_000L;
          wall env jump;
          Alcotest.(check int)
            "no restart before native backoff" 1 (S.generation supervisor);
          mono env 100_000_000L;
          Alcotest.(check int) "restart at native backoff" 2 (S.generation supervisor);
          (match Eio.Stream.take (S.events supervisor) with
          | S.Started 2 -> ()
          | _ -> assert false);
          S.stop supervisor;
          stopped supervisor;
          Alcotest.(check (list int))
            "current child retired on stop" [ Sys.sigterm ]
            (Ox_test.Process.signals fake);
          S.stop supervisor;
          mono env 1_000_000_000L;
          Alcotest.(check int)
            "stop prevents any later launch" 2 (S.generation supervisor)))

let supervised_elapsed ~caps jump () =
  Ox_test.run (fun env sw ->
      let fake =
        Ox_test.Process.make
          [
            Ox_test.Process.Exit (`Exited 1);
            Ox_test.Process.Exit (`Exited 2);
            Ox_test.Process.Block_until_signal;
          ]
      in
      let observed = ref [] in
      let schedule =
        Ox.Schedule.modify_delay
          (fun (_, elapsed) _ ->
            observed := Ox.Duration.to_ms elapsed :: !observed;
            Ox.Duration.ms 100)
          (Ox.Schedule.both (Ox.Schedule.recurs 2) Ox.Schedule.elapsed)
      in
      let supervisor =
        S.start ~sw ~clock:(process_clock env) ~schedule ~spawn:(fun ~sw ->
            C.spawn ~caps ~sw ~clock:(process_clock env) ~mgr:(Ox_test.Process.mgr fake)
              ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      Fun.protect
        ~finally:(fun () ->
          wall env 1_000_000.;
          mono env 9_000_000_000_000_000_000L;
          S.stop supervisor)
        (fun () ->
          settle ();
          wall env jump;
          mono env 100_000_000L;
          Alcotest.(check (list int))
            "elapsed Schedule output ignores wall correction" [ 100; 0 ] !observed;
          S.stop supervisor))

let supervised_precision ~caps () =
  Ox_test.run (fun env sw ->
      let origin = 4_000_000_000_000_900_000L in
      mono env origin;
      let fake =
        Ox_test.Process.make
          [
            Ox_test.Process.Exit (`Exited 1);
            Ox_test.Process.Block_until_signal;
            Ox_test.Process.Block_until_signal;
            Ox_test.Process.Block_until_signal;
          ]
      in
      let observed = ref [] in
      let current = ref None in
      let schedule =
        Ox.Schedule.modify_delay
          (fun (_, elapsed) _ ->
            observed := Ox.Duration.to_ms elapsed :: !observed;
            Ox.Duration.zero)
          (Ox.Schedule.both (Ox.Schedule.recurs 3) Ox.Schedule.elapsed)
      in
      let supervisor =
        S.start ~sw ~clock:(process_clock env) ~schedule ~spawn:(fun ~sw ->
            let child =
              C.spawn ~caps ~sw ~clock:(process_clock env) ~mgr:(Ox_test.Process.mgr fake)
                ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ()
            in
            (match child with Ok child -> current := Some child | Error _ -> ());
            child)
      in
      Fun.protect
        ~finally:(fun () -> S.stop supervisor)
        (fun () ->
          settle ();
          let exit_current () =
            match !current with
            | Some child ->
                C.signal child Sys.sigterm;
                settle ()
            | None -> Alcotest.fail "missing current child"
          in
          mono env (Int64.add origin 200_000L);
          exit_current ();
          mono env (Int64.add origin 1_100_000L);
          exit_current ();
          Alcotest.(check (list int))
            "subtract native origin before truncating milliseconds" [ 1; 0; 0 ] !observed;
          Alcotest.(check int) "four child generations" 4 (S.generation supervisor);
          S.stop supervisor))

let stop_during_backoff ~caps () =
  Ox_test.run (fun env sw ->
      let fake = Ox_test.Process.make [ Ox_test.Process.Exit (`Exited 1) ] in
      let supervisor =
        S.start ~sw ~clock:(process_clock env)
          ~schedule:(Ox.Schedule.spaced (Ox.Duration.ms 100))
          ~spawn:(fun ~sw ->
            C.spawn ~caps ~sw ~clock:(process_clock env) ~mgr:(Ox_test.Process.mgr fake)
              ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero ~fds:[] ())
      in
      (match Eio.Stream.take (S.events supervisor) with
      | S.Started 1 -> ()
      | _ -> assert false);
      (match Eio.Stream.take (S.events supervisor) with
      | S.Exited (1, _) -> ()
      | _ -> assert false);
      settle ();
      wall env (-1_000.);
      S.stop supervisor;
      stopped supervisor;
      mono env 1_000_000_000L;
      wall env 1_000_000.;
      Alcotest.(check int)
        "backoff cancellation launches no child" 1 (S.generation supervisor);
      S.stop supervisor)

let supervised_join ~caps owner_cancel () =
  with_retirement (fun env sw t ->
      let context, context_u = Eio.Promise.create () in
      let ready, ready_u = Eio.Promise.create () in
      let result =
        fork_exit ~sw (fun _scope_sw ->
            Eio.Cancel.sub (fun ctx ->
                Eio.Promise.resolve context_u ctx;
                Eio.Switch.run (fun owner ->
                    let supervisor =
                      S.start ~sw:owner ~clock:(process_clock env)
                        ~schedule:Ox.Schedule.forever ~spawn:(fun ~sw ->
                          Ok (spawn ~caps env ~sw t))
                    in
                    (match Eio.Stream.take (S.events supervisor) with
                    | S.Started 1 -> ()
                    | _ -> assert false);
                    Eio.Promise.resolve ready_u supervisor;
                    if owner_cancel then Eio.Fiber.await_cancel () else S.stop supervisor);
                Eio.Cancel.check ctx;
                Ok ()))
      in
      let supervisor = Eio.Promise.await ready in
      Eio.Cancel.cancel (Eio.Promise.await context) Exit;
      settle ();
      wall env (-1_000.);
      mono env 100_000_000L;
      signals [ Sys.sigterm; Sys.sigkill ] t;
      Alcotest.(check bool)
        "worker waits for physical finalizer" false
        (Eio.Promise.is_resolved result);
      Alcotest.(check int)
        "no premature Stopped" 0
        (Eio.Stream.length (S.events supervisor));
      release t;
      assert_interrupt result;
      Alcotest.(check bool) "physical finalizer joined" true t.finalized;
      stopped supervisor;
      S.stop supervisor;
      Alcotest.(check int) "no cancellation restart" 1 (S.generation supervisor))

let () =
  let caps = Ox_test.powerbox () in
  Alcotest.run "process monotonic safety"
    [
      ( "grace",
        List.map
          (fun (name, jump) -> Alcotest.test_case name `Quick (child_grace ~caps jump))
          [ ("native control", 0.); ("wall forward", 1_000.); ("wall backward", -1_000.) ]
      );
      ( "backoff",
        List.map
          (fun (name, jump) ->
            Alcotest.test_case name `Quick (supervised_backoff ~caps jump))
          [ ("native control", 0.); ("wall forward", 1_000.); ("wall backward", -1_000.) ]
      );
      ( "elapsed",
        List.map
          (fun (name, jump) ->
            Alcotest.test_case name `Quick (supervised_elapsed ~caps jump))
          [ ("native control", 0.); ("wall forward", 1_000.); ("wall backward", -1_000.) ]
      );
      ( "precision",
        [
          Alcotest.test_case "large origin and sub-millisecond carry" `Quick
            (supervised_precision ~caps);
        ] );
      ( "retirement",
        [
          Alcotest.test_case "stop during backoff" `Quick (stop_during_backoff ~caps);
          Alcotest.test_case "cancelled Child.stop joins" `Quick
            (child_cancelled_stop ~caps);
          Alcotest.test_case "cancelled Supervised.stop joins" `Quick
            (supervised_join ~caps false);
          Alcotest.test_case "owner cancellation joins" `Quick
            (supervised_join ~caps true);
        ] );
    ]
