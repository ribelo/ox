(* Row 47, story 14: Agent, state owned by one fiber and changed by serialized closures.
   Every case cites nactor-75ef. There are no wall-clock sleeps: ordering is forced with
   promises and yields under Eio_mock's scheduler. *)
open Ox

let check_bool = Alcotest.(check bool)
let check_int = Alcotest.(check int)

exception Boom of string

let run f = Eio_mock.Backend.run_full (fun env -> f env#clock)

let yields n =
  for _ = 1 to n do
    Eio.Fiber.yield ()
  done

let ok = function Ok v -> v | Error `Agent_stopped -> Alcotest.fail "agent stopped"
let create ?capacity ~sw init = Agent.create ?capacity ~sw ~init:(fun () -> init) ()

(* A consumer using all four operations, with no message declaration anywhere. *)
let four_operations () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let counter = create ~sw 0 in
          ok (Agent.update counter ~fn:(fun n -> n + 1));
          ok (Agent.cast counter ~fn:(fun n -> n + 10));
          check_int "read after cast sees the cast" 11
            (ok (Agent.get counter ~fn:(fun n -> n)));
          check_int "get_and_update replies with the previous value" 11
            (ok (Agent.get_and_update counter ~fn:(fun n -> (n, n * 2))));
          check_int "and commits the new state" 22 (ok (Agent.get counter ~fn:Fun.id))))

let mixed_reply_types () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let agent = create ~sw [ 1; 2; 3 ] in
          (* one handle, replies of unrelated types, no witness *)
          let length = ok (Agent.get agent ~fn:List.length) in
          let text =
            ok
              (Agent.get agent ~fn:(fun l -> String.concat "," (List.map string_of_int l)))
          in
          let sum =
            ok
              (Agent.get_and_update agent ~fn:(fun l ->
                   (List.fold_left ( + ) 0 l, 4 :: l)))
          in
          let head =
            ok (Agent.get agent ~fn:(function h :: _ -> Some h | [] -> None))
          in
          check_int "length" 3 length;
          Alcotest.(check string) "text" "1,2,3" text;
          check_int "sum" 6 sum;
          Alcotest.(check (option int)) "head" (Some 4) head))

let atomic_get_and_update () =
  run (fun _ ->
      let previous = ref [] in
      Eio.Switch.run (fun sw ->
          let counter = create ~sw 0 in
          for _ = 1 to 10 do
            Eio.Fiber.fork ~sw (fun () ->
                (* each increment yields between read and write inside the closure: without
                   serialization two callers would see the same previous value *)
                let seen =
                  ok
                    (Agent.get_and_update counter ~fn:(fun n ->
                         Eio.Fiber.yield ();
                         (n, n + 1)))
                in
                previous := seen :: !previous)
          done);
      Alcotest.(check (list int))
        "every previous value exactly once"
        [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9 ]
        (List.sort compare !previous))

let concurrent_increments () =
  run (fun _ ->
      let final = ref 0 in
      Eio.Switch.run (fun sw ->
          let counter = create ~sw 0 in
          Eio.Fiber.all
            (List.init 8 (fun _ () ->
                 for _ = 1 to 25 do
                   ok (Agent.update counter ~fn:(fun n -> n + 1));
                   ok (Agent.cast counter ~fn:(fun n -> n + 1))
                 done));
          final := ok (Agent.get counter ~fn:Fun.id));
      check_int "no lost update" 400 !final)

let barriers () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let agent = create ~sw "a" in
          ok (Agent.update agent ~fn:(fun s -> s ^ "b"));
          Alcotest.(check string)
            "read-after-update" "ab"
            (ok (Agent.get agent ~fn:Fun.id));
          ok (Agent.cast agent ~fn:(fun s -> s ^ "c"));
          ok (Agent.cast agent ~fn:(fun s -> s ^ "d"));
          Alcotest.(check string)
            "read-after-cast: acceptance order, so the cast bodies ran first" "abcd"
            (ok (Agent.get agent ~fn:Fun.id))))

let init_once_in_owner () =
  run (fun _ ->
      let who = Eio.Fiber.create_key () in
      let calls = ref 0 and init_saw = ref None and callback_saw = ref [] in
      Eio.Switch.run (fun sw ->
          (* the owner is forked here and inherits this binding; each caller rebinds *)
          let agent =
            Eio.Fiber.with_binding who "owner" (fun () ->
                Agent.create ~sw
                  ~init:(fun () ->
                    incr calls;
                    init_saw := Eio.Fiber.get who;
                    0)
                  ())
          in
          for _ = 1 to 3 do
            Eio.Fiber.with_binding who "caller" (fun () ->
                ignore
                  (ok
                     (Agent.get agent ~fn:(fun s ->
                          callback_saw := Eio.Fiber.get who :: !callback_saw;
                          s))))
          done;
          check_int "init ran once" 1 !calls;
          check_bool "init ran in the owner fiber" true (!init_saw = Some "owner");
          check_bool "and so did every closure" true
            (!callback_saw = [ Some "owner"; Some "owner"; Some "owner" ])))

let no_overlap () =
  run (fun _ ->
      let inside = ref false and overlapped = ref false in
      let step state =
        if !inside then overlapped := true;
        inside := true;
        yields 3;
        inside := false;
        state + 1
      in
      Eio.Switch.run (fun sw ->
          let agent = create ~sw 0 in
          for _ = 1 to 4 do
            Eio.Fiber.fork ~sw (fun () ->
                ok (Agent.update agent ~fn:step);
                ignore (ok (Agent.get agent ~fn:step)))
          done);
      check_bool "callbacks, reads included, never overlap even when one yields" false
        !overlapped)

let capacity_one () =
  run (fun _ ->
      let applied = ref 0 in
      Eio.Switch.run (fun sw ->
          let gate, release = Eio.Promise.create () in
          let agent = create ~capacity:1 ~sw 0 in
          (* the owner is held inside a closure, so the mailbox fills behind it *)
          Eio.Fiber.fork ~sw (fun () ->
              ok
                (Agent.update agent ~fn:(fun n ->
                     Eio.Promise.await gate;
                     incr applied;
                     n + 1)));
          yields 3;
          check_bool "cast is accepted while the owner is busy" true
            (Agent.cast agent ~fn:(fun n ->
                 incr applied;
                 n + 10)
            = Ok ());
          check_int "accepted is not executed" 0 !applied;
          let second = ref false and updated = ref false in
          Eio.Fiber.fork ~sw (fun () ->
              ok
                (Agent.cast agent ~fn:(fun n ->
                     incr applied;
                     n + 100));
              second := true);
          yields 3;
          check_bool "a full mailbox blocks cast" false !second;
          Eio.Fiber.fork ~sw (fun () ->
              ok
                (Agent.update agent ~fn:(fun n ->
                     incr applied;
                     n + 1000));
              updated := true);
          yields 3;
          Eio.Promise.resolve release ();
          yields 20;
          check_bool "the blocked cast was admitted once there was room" true !second;
          check_bool "update acknowledges after its commit" true !updated;
          check_int "all four ran" 4 !applied;
          check_int "in acceptance order, all applied" 1111
            (ok (Agent.get agent ~fn:Fun.id))))

let update_acknowledges_after_commit () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let gate, release = Eio.Promise.create () in
          let agent = create ~sw 0 in
          let acked = ref false in
          Eio.Fiber.fork ~sw (fun () ->
              ok
                (Agent.update agent ~fn:(fun n ->
                     Eio.Promise.await gate;
                     n + 1));
              (* the acknowledgement is only ever delivered after the commit *)
              acked := true;
              check_int "committed before acknowledged" 1
                (ok (Agent.get agent ~fn:Fun.id)));
          yields 3;
          check_bool "no acknowledgement before the closure ran" false !acked;
          Eio.Promise.resolve release ();
          yields 10;
          check_bool "acknowledged" true !acked))

(* ---- cancellation and lifecycle ------------------------------------------------------- *)

let observe outcome f =
  match f () with
  | Ok _ -> outcome := "returned"
  | Error `Agent_stopped -> outcome := "stopped"
  | exception Eio.Cancel.Cancelled _ -> outcome := "cancelled"

let caller_cancelled () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let gate, release = Eio.Promise.create () in
          let agent = create ~capacity:1 ~sw 0 in
          Eio.Fiber.fork ~sw (fun () ->
              ok
                (Agent.update agent ~fn:(fun n ->
                     Eio.Promise.await gate;
                     n + 1)));
          yields 3;
          Eio.Fiber.fork ~sw (fun () -> ok (Agent.cast agent ~fn:(fun n -> n + 10)));
          yields 3;
          (* before admission: blocked on a full mailbox *)
          let before = ref "" and cc_before = ref None in
          Eio.Fiber.fork ~sw (fun () ->
              observe before (fun () ->
                  Eio.Cancel.sub (fun cc ->
                      cc_before := Some cc;
                      Agent.cast agent ~fn:(fun n -> n + 100))));
          yields 3;
          let cancel_context =
            match !cc_before with
            | Some context -> context
            | None ->
                Alcotest.fail "pre-admission caller cancellation context was not captured"
          in
          Eio.Cancel.cancel cancel_context (Failure "caller gone");
          yields 3;
          Alcotest.(check string)
            "cancelled before admission stays a cancellation" "cancelled" !before;
          (* after admission: queued, the caller stops waiting *)
          let after = ref "" and cc_after = ref None in
          Eio.Fiber.fork ~sw (fun () ->
              observe after (fun () ->
                  Eio.Cancel.sub (fun cc ->
                      cc_after := Some cc;
                      Agent.get_and_update agent ~fn:(fun n -> (n, n + 1000)))));
          Eio.Promise.resolve release ();
          yields 1;
          (match !cc_after with
          | Some cc -> Eio.Cancel.cancel cc (Failure "caller gone")
          | None -> ());
          yields 20;
          Alcotest.(check string)
            "cancelled after admission stays a cancellation" "cancelled" !after;
          (* the accepted operations were not rolled back: 1 + 10, the cancelled one whole *)
          check_int "an admitted operation is not retracted" 1011
            (ok (Agent.get agent ~fn:Fun.id))))

let owner_ends_releases_waiters () =
  run (fun _ ->
      let answers = ref [] and blocked_cast = ref None in
      Eio.Switch.run (fun outer ->
          let gate, release = Eio.Promise.create () in
          ignore
            (Scope.run (fun sw ->
                 let agent = create ~capacity:1 ~sw 0 in
                 Eio.Fiber.fork ~sw:outer (fun () ->
                     let reply =
                       Agent.update agent ~fn:(fun _ ->
                           Eio.Promise.await gate;
                           raise (Boom "owner"))
                     in
                     answers := ("crash", reply) :: !answers);
                 yields 3;
                 Eio.Fiber.fork ~sw:outer (fun () ->
                     let reply = Agent.get agent ~fn:ignore in
                     answers := ("queued", reply) :: !answers);
                 yields 3;
                 (* the mailbox (capacity 1) is now full: this producer blocks in admission *)
                 Eio.Fiber.fork ~sw:outer (fun () ->
                     blocked_cast := Some (Agent.cast agent ~fn:(fun n -> n + 1)));
                 yields 3;
                 check_bool "the producer is blocked while the owner lives" true
                   (!blocked_cast = None);
                 Eio.Promise.resolve release ();
                 yields 10;
                 Ok ()));
          yields 10;
          let crash_reply =
            match List.assoc_opt "crash" !answers with
            | Some reply -> reply
            | None -> Alcotest.fail "agent crash reply was not recorded"
          in
          check_bool "the reply whose closure raised is released" true
            (crash_reply = Error `Agent_stopped);
          let queued_reply =
            match List.assoc_opt "queued" !answers with
            | Some reply -> reply
            | None -> Alcotest.fail "agent queued reply was not recorded"
          in
          check_bool "a queued reply is released" true
            (queued_reply = Error `Agent_stopped);
          check_bool "a producer blocked on a full mailbox is released" true
            (!blocked_cast = Some (Error `Agent_stopped))))

let closed_after_switch () =
  run (fun _ ->
      let agent =
        Eio.Switch.run (fun sw ->
            let agent = create ~sw 1 in
            check_int "alive" 1 (ok (Agent.get agent ~fn:Fun.id));
            agent)
      in
      check_bool "get on a closed agent" true
        (Agent.get agent ~fn:Fun.id = Error `Agent_stopped);
      check_bool "update" true (Agent.update agent ~fn:Fun.id = Error `Agent_stopped);
      check_bool "get_and_update" true
        (Agent.get_and_update agent ~fn:(fun s -> (s, s)) = Error `Agent_stopped);
      check_bool "cast" true (Agent.cast agent ~fn:Fun.id = Error `Agent_stopped))

let external_cancel_of_switch () =
  run (fun _ ->
      let answers = ref [] in
      Eio.Switch.run (fun outer ->
          let gate, release = Eio.Promise.create () in
          let cc = ref None in
          Eio.Fiber.fork ~sw:outer (fun () ->
              match
                Eio.Cancel.sub (fun c ->
                    cc := Some c;
                    Eio.Switch.run (fun sw ->
                        let agent = create ~sw 0 in
                        Eio.Fiber.fork ~sw:outer (fun () ->
                            let reply =
                              Agent.update agent ~fn:(fun n ->
                                  Eio.Promise.await gate;
                                  n)
                            in
                            answers := ("held", reply) :: !answers);
                        Eio.Fiber.fork ~sw:outer (fun () ->
                            let reply = Agent.get agent ~fn:ignore in
                            answers := ("queued", reply) :: !answers);
                        Eio.Fiber.await_cancel ()))
              with
              | () -> ()
              | exception Eio.Cancel.Cancelled _ -> ());
          yields 5;
          let cancel_context =
            match !cc with
            | Some context -> context
            | None -> Alcotest.fail "agent scope cancellation context was not captured"
          in
          Eio.Cancel.cancel cancel_context (Failure "stop the scope");
          yields 3;
          Eio.Promise.resolve release ();
          yields 10;
          let held_reply =
            match List.assoc_opt "held" !answers with
            | Some reply -> reply
            | None -> Alcotest.fail "agent held reply was not recorded"
          in
          check_bool "the closure in flight finished" true (held_reply = Ok ());
          let queued_reply =
            match List.assoc_opt "queued" !answers with
            | Some reply -> reply
            | None -> Alcotest.fail "agent queued reply was not recorded"
          in
          check_bool "the queued reply is released, not left waiting" true
            (queued_reply = Error `Agent_stopped)))

(* ---- defects: same exception, no leak, nothing swallowed --------------------------------- *)

(* [Scope.run] returning proves every fiber the scope started has finished. *)
let defect_in name ~init use =
  run (fun _ ->
      let boom = Boom name in
      let exit =
        Scope.run (fun sw ->
            let agent = Agent.create ~sw ~init:(init boom) () in
            ignore (use agent boom);
            yields 5;
            Ok ())
      in
      match exit with
      | Exit.Failure (Cause.Die (ex, _)) ->
          check_bool
            (name ^ ": the same exception fails the owning switch")
            true (ex == boom)
      | Exit.Failure c -> Alcotest.failf "%s: %a" name (Cause.pp Format.pp_print_string) c
      | Exit.Success () -> Alcotest.failf "%s: the defect was swallowed" name)

let healthy _ () = 0

let defects () =
  defect_in "init"
    ~init:(fun boom () -> raise boom)
    (fun agent _ -> Agent.get agent ~fn:Fun.id);
  defect_in "get" ~init:healthy (fun agent boom ->
      Agent.get agent ~fn:(fun _ -> raise boom));
  defect_in "update" ~init:healthy (fun agent boom ->
      Agent.update agent ~fn:(fun _ -> raise boom) |> Stdlib.Result.map (fun () -> 0));
  defect_in "get_and_update" ~init:healthy (fun agent boom ->
      Agent.get_and_update agent ~fn:(fun _ -> raise boom));
  defect_in "cast" ~init:healthy (fun agent boom ->
      (* a cast's closure raises later, in the owner: the caller has long returned *)
      Agent.cast agent ~fn:(fun _ -> raise boom) |> Stdlib.Result.map (fun () -> 0))

(* ---- typed refusal ----------------------------------------------------------------------- *)

let typed_refusal () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let agent = create ~sw 5 in
          check_bool "update_result Ok commits" true
            (Agent.update_result agent ~fn:(fun n -> Ok (n + 1)) = Ok ());
          check_bool "update_result Error goes to the caller" true
            (Agent.update_result agent ~fn:(fun _ -> Error `Too_big) = Error `Too_big);
          check_int "and leaves the state" 6 (ok (Agent.get agent ~fn:Fun.id));
          check_bool "get_and_update_result Ok replies and commits" true
            (Agent.get_and_update_result agent ~fn:(fun n -> Ok (n, n * 2)) = Ok 6);
          check_bool "get_and_update_result Error is returned" true
            (Agent.get_and_update_result agent ~fn:(fun n ->
                 if n > 10 then Error `Too_big else Ok (n, n))
            = Error `Too_big);
          check_int "the agent goes on, state untouched" 12
            (ok (Agent.get agent ~fn:Fun.id))))

let capacity_validated () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          Alcotest.check_raises "capacity must be positive"
            (Invalid_argument "Ox.Agent.create: capacity must be at least 1") (fun () ->
              ignore (Agent.create ~capacity:0 ~sw ~init:(fun () -> 0) ()))))

let tests =
  [
    ( "Agent nactor-75ef",
      [
        Alcotest.test_case "nactor-75ef all four operations, no message type" `Quick
          four_operations;
        Alcotest.test_case "nactor-75ef mixed reply types on one handle" `Quick
          mixed_reply_types;
        Alcotest.test_case "nactor-75ef get_and_update returns each previous value once"
          `Quick atomic_get_and_update;
        Alcotest.test_case "nactor-75ef concurrent increments" `Quick
          concurrent_increments;
        Alcotest.test_case "nactor-75ef read-after-update and read-after-cast" `Quick
          barriers;
        Alcotest.test_case "nactor-75ef init once, in the owner" `Quick init_once_in_owner;
        Alcotest.test_case "nactor-75ef no overlapping callbacks" `Quick no_overlap;
        Alcotest.test_case "nactor-75ef capacity one: cast backpressure" `Quick
          capacity_one;
        Alcotest.test_case "nactor-75ef update acknowledges after commit" `Quick
          update_acknowledges_after_commit;
        Alcotest.test_case "nactor-75ef caller cancelled before and after admission"
          `Quick caller_cancelled;
        Alcotest.test_case "nactor-75ef owner ends: every waiter and producer released"
          `Quick owner_ends_releases_waiters;
        Alcotest.test_case "nactor-75ef closed after the switch" `Quick
          closed_after_switch;
        Alcotest.test_case "nactor-75ef external cancellation of the switch" `Quick
          external_cancel_of_switch;
        Alcotest.test_case "nactor-75ef defects in init and every callback" `Quick defects;
        Alcotest.test_case "nactor-75ef typed refusal" `Quick typed_refusal;
        Alcotest.test_case "nactor-75ef capacity validated" `Quick capacity_validated;
      ] );
  ]
