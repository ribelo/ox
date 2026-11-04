(* ^nspawn-lhyg: a Service stores a spawner at create and forks with it later. *)
open Ox

module Ticker = struct
  type deps = { spawner : string Spawner.t }
  type t = { deps : deps; ticks : int ref }

  let create deps = { deps; ticks = ref 0 }

  (* Called after [create] returned: the fork authority comes from the deps. *)
  let tick_later t = Spawner.fork t.deps.spawner (fun () -> incr t.ticks)

  let fail_later t =
    ignore
      (Spawner.fork_error t.deps.spawner (fun () -> Error "stopped")
        : (unit, string) Scope.fork)
end

let forks_after_create () =
  Eio_mock.Backend.run (fun () ->
      Eio.Switch.run (fun sw ->
          let ticks =
            Scope.supervised_error ~sw (fun scope ->
                let service = Ticker.create { spawner = Scope.spawner scope } in
                Ticker.tick_later service;
                Ticker.tick_later service;
                Ok service.ticks)
          in
          match ticks with
          | Ok ticks -> Alcotest.(check int) "both later forks ran" 2 !ticks
          | Error e -> Alcotest.fail e))

let error_ends_scope () =
  Eio_mock.Backend.run (fun () ->
      Eio.Switch.run (fun sw ->
          let released = ref false in
          let result =
            Scope.supervised_error ~sw (fun scope ->
                let spawner = Scope.spawner scope in
                Spawner.on_release spawner (fun () -> released := true);
                Ticker.fail_later (Ticker.create { spawner });
                Eio.Fiber.await_cancel ())
          in
          Alcotest.(check (result unit string))
            "the fork's error ends the scope" (Error "stopped") result;
          Alcotest.(check bool) "release ran" true !released))

let () =
  Alcotest.run "Spawner"
    [
      ( "spawner",
        [
          Alcotest.test_case "^nspawn-lhyg forks after create" `Quick forks_after_create;
          Alcotest.test_case "^nspawn-lhyg typed error ends the scope" `Quick
            error_ends_scope;
        ] );
    ]
