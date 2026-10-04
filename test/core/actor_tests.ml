(* Row 47: Actor, a typed mailbox over a state fold. Every case cites its story IDs
   (nactor IDs). Story 12 (^nactor-8z1n) is Leash's own registry suite, run against this
   tree; it is not repeated here. *)
open Ox

let check_bool = Alcotest.(check bool)
let check_int = Alcotest.(check int)

exception Boom of string

type msg =
  | Add of int
  | Get
  | Refuse
  | Crash of exn
  | Slow of int * unit Eio.Promise.t
  | Slow_crash of unit Eio.Promise.t * exn

(* The state is a running total; the reply is the total after the message. *)
let handle state = function
  | Add n -> Ok (state + n, state + n)
  | Get -> Ok (state, state)
  | Refuse -> Error `Refused
  | Crash ex -> raise ex
  | Slow (n, gate) ->
      Eio.Promise.await gate;
      Ok (state + n, state + n)
  | Slow_crash (gate, ex) ->
      Eio.Promise.await gate;
      raise ex

let run f = Eio_mock.Backend.run_full (fun env -> f env#clock)

let yields n =
  for _ = 1 to n do
    Eio.Fiber.yield ()
  done

(* ---- nactor-agcr nactor-jhl2: create, ask, tell ---------------------------------------- *)

let ask_and_tell () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let actor = Actor.create ~sw ~init:0 ~handle () in
          check_bool "ask replies with the handler's reply" true
            (Actor.ask actor (Add 2) = Ok 2);
          Actor.tell actor (Add 3);
          Actor.tell actor (Add 4);
          check_bool "tell returned without a reply; a later ask sees its effect" true
            (Actor.ask actor Get = Ok 9);
          check_int "state" 9 (Actor.state actor)))

(* ---- nactor-mb6v: arrival order, one at a time ---------------------------------------- *)

let ordering () =
  run (fun _ ->
      let seen = ref [] and inside = ref false and overlapped = ref false in
      let handle log msg =
        if !inside then overlapped := true;
        inside := true;
        yields 2;
        (* the handler suspends: nothing else may run inside it *)
        seen := msg :: !seen;
        inside := false;
        Ok (msg :: log, ())
      in
      Eio.Switch.run (fun sw ->
          let actor = Actor.create ~sw ~init:[] ~handle () in
          let sender name =
            Eio.Fiber.fork ~sw (fun () ->
                for i = 1 to 5 do
                  Actor.tell actor (name, i);
                  Eio.Fiber.yield ()
                done)
          in
          sender "a";
          sender "b";
          sender "c";
          while List.length (Actor.state actor) < 15 do
            Eio.Fiber.yield ()
          done;
          let arrival = List.rev !seen in
          List.iter
            (fun name ->
              Alcotest.(check (list int))
                (name ^ ": each sender's messages in send order")
                [ 1; 2; 3; 4; 5 ]
                (List.filter_map
                   (fun (n, i) -> if n = name then Some i else None)
                   arrival))
            [ "a"; "b"; "c" ];
          check_bool "never two handlers at once" false !overlapped;
          check_bool "the state folded exactly what was handled, in order" true
            (List.rev (Actor.state actor) = arrival)))

(* ---- nactor-7qi7: Error leaves the state and the actor alone --------------------------- *)

let error_leaves_state () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let actor = Actor.create ~sw ~init:10 ~handle () in
          check_bool "typed failure reaches the asker" true
            (Actor.ask actor Refuse = Error `Refused);
          check_int "state unchanged" 10 (Actor.state actor);
          check_bool "the actor goes on" true (Actor.ask actor (Add 1) = Ok 11);
          (* a told message that fails has nobody to tell; the actor is unaffected *)
          Actor.tell actor Refuse;
          check_bool "still serving" true (Actor.ask actor Get = Ok 11);
          let seen = Actor.changes actor in
          ((* ^nlint-hxar: Refuse is scripted to fail without changing state; the stream assertion below checks that it publishes no state. *)
           let _refused_ask_result = Actor.ask actor Refuse in
           ());
          ((* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
           let _ask_result = Actor.ask actor (Add 1) in
           ());
          check_bool "a failed handler publishes no state" true
            (Actor.Changes.next seen = Some 12)))

(* ---- nactor-pxfz: a handler exception ends the actor and fails its switch ------------- *)

let exception_ends_actor () =
  run (fun _ ->
      let boom = Boom "handler" in
      let answers = ref [] in
      Eio.Switch.run (fun outer ->
          let gate, release = Eio.Promise.create () in
          let exit =
            Scope.run (fun sw ->
                let actor = Actor.create ~sw ~init:0 ~handle () in
                (* askers outside the failing switch see the answer, not a cancellation *)
                List.iter
                  (fun (i, msg) ->
                    Eio.Fiber.fork ~sw:outer (fun () ->
                        let reply = Actor.ask actor msg in
                        answers := (i, reply) :: !answers))
                  [ (1, Add 1); (2, Slow_crash (gate, boom)); (3, Add 3); (4, Add 4) ];
                yields 3;
                Eio.Promise.resolve release ();
                yields 5;
                Ok ())
          in
          (match exit with
          | Exit.Failure (Cause.Die (ex, _)) ->
              check_bool "the same exception, classified a defect" true (ex == boom)
          | _ -> Alcotest.fail "a handler exception must fail the scope as a defect");
          yields 10;
          let answer i = List.assoc_opt i !answers in
          check_bool "the message handled before the crash is answered" true
            (answer 1 = Some (Ok 1));
          check_bool "the ask whose handler raised is answered Actor_stopped" true
            (answer 2 = Some (Error `Actor_stopped));
          check_bool "queued asks are answered Actor_stopped" true
            (answer 3 = Some (Error `Actor_stopped)
            && answer 4 = Some (Error `Actor_stopped))))

let in_flight_ask_on_crash () =
  run (fun _ ->
      let answer = ref None in
      Eio.Switch.run (fun outer ->
          ignore
            (Scope.run (fun sw ->
                 let actor = Actor.create ~sw ~init:0 ~handle () in
                 Eio.Fiber.fork ~sw:outer (fun () ->
                     answer := Some (Actor.ask actor (Crash (Boom "in flight"))));
                 yields 5;
                 Ok ()));
          yields 3;
          check_bool "the ask whose handler raised is answered Actor_stopped" true
            (!answer = Some (Error `Actor_stopped))))

let ask_after_stop () =
  run (fun _ ->
      let actor =
        Eio.Switch.run (fun sw ->
            let actor = Actor.create ~sw ~init:5 ~handle () in
            ((* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
             let _ask_result = Actor.ask actor (Add 1) in
             ());
            actor)
      in
      check_bool "ask on a stopped actor" true (Actor.ask actor Get = Error `Actor_stopped);
      check_bool "try_tell on a stopped actor" false (Actor.try_tell actor Get);
      Actor.tell actor Get;
      check_int "the final state stays readable" 6 (Actor.state actor))

(* ---- nactor-6z3i: the state stream ------------------------------------------------------ *)

let changes_stream () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let actor = Actor.create ~sw ~init:0 ~handle () in
          let first = Actor.changes actor and second = Actor.changes actor in
          List.iter
            (fun n ->
              (* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
              let _ask_result = Actor.ask actor (Add n) in
              ())
            [ 1; 2; 3 ];
          let take subscription n =
            List.init n (fun _ -> Actor.Changes.next subscription)
          in
          Alcotest.(check (list (option int)))
            "states after each successful handler, in order" [ Some 1; Some 3; Some 6 ]
            (take first 3);
          Alcotest.(check (list (option int)))
            "every subscriber has its own buffer" [ Some 1; Some 3; Some 6 ]
            (take second 3);
          check_int "nothing dropped" 0 (Actor.Changes.dropped first);
          (* overflow: a lagging observer loses the oldest states and counts them *)
          let slow = Actor.changes ~capacity:2 actor in
          for n = 1 to 5 do
            (* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
            let _ask_result = Actor.ask actor (Add n) in
            ()
          done;
          (* totals 7, 9, 12, 16, 21 *)
          check_int "the three oldest were dropped" 3 (Actor.Changes.dropped slow);
          Alcotest.(check (list (option int)))
            "the newest survive" [ Some 16; Some 21 ] (take slow 2);
          Actor.Changes.close first;
          check_bool "a closed subscription ends" true (Actor.Changes.next first = None);
          check_bool "closing twice is harmless" true
            (Actor.Changes.close first;
             true)))

let changes_end_with_actor () =
  run (fun _ ->
      let subscription =
        Eio.Switch.run (fun sw ->
            let actor = Actor.create ~sw ~init:0 ~handle () in
            let subscription = Actor.changes actor in
            ((* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
             let _ask_result = Actor.ask actor (Add 1) in
             ());
            ((* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
             let _ask_result = Actor.ask actor (Add 2) in
             ());
            subscription)
      in
      Alcotest.(check (list (option int)))
        "buffered states, then the end"
        [ Some 1; Some 3; None; None ]
        (List.init 4 (fun _ -> Actor.Changes.next subscription));
      let late =
        Eio.Switch.run (fun sw ->
            let actor = Actor.create ~sw ~init:0 ~handle () in
            actor)
        |> fun actor -> Actor.changes actor
      in
      check_bool "subscribing to a stopped actor has already ended" true
        (Actor.Changes.next late = None))

(* ---- nactor-l87k: a snapshot read does not queue --------------------------------------- *)

let state_snapshot () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let gate, release = Eio.Promise.create () in
          let actor = Actor.create ~sw ~init:0 ~handle () in
          ((* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
           let _ask_result = Actor.ask actor (Add 1) in
           ());
          Actor.tell actor (Slow (10, gate));
          Actor.tell actor (Add 100);
          yields 3;
          check_int "read while the actor is busy: the last completed state" 1
            (Actor.state actor);
          Eio.Promise.resolve release ();
          check_bool "and the queue behind it was untouched" true
            (Actor.ask actor Get = Ok 111);
          check_int "state" 111 (Actor.state actor)))

(* ---- nactor-512k: a bounded mailbox ---------------------------------------------------- *)

let backpressure () =
  run (fun _ ->
      Eio.Switch.run (fun sw ->
          let gate, release = Eio.Promise.create () in
          let actor = Actor.create ~capacity:2 ~sw ~init:0 ~handle () in
          Actor.tell actor (Slow (1, gate));
          yields 3;
          (* the actor holds Slow; two more fit *)
          check_bool "first fits" true (Actor.try_tell actor (Add 1));
          check_bool "second fits" true (Actor.try_tell actor (Add 1));
          check_bool "a full mailbox refuses try_tell" false
            (Actor.try_tell actor (Add 1));
          let told = ref false in
          Eio.Fiber.fork ~sw (fun () ->
              Actor.tell actor (Add 1);
              told := true);
          yields 3;
          check_bool "tell blocks while the mailbox is full" false !told;
          Eio.Promise.resolve release ();
          yields 10;
          check_bool "and goes through once there is room" true !told;
          check_int "every accepted message was handled" 4 (Actor.state actor);
          Alcotest.check_raises "capacity must be positive"
            (Invalid_argument "Ox.Actor.create: capacity must be at least 1") (fun () ->
              ignore (Actor.create ~capacity:0 ~sw ~init:0 ~handle ()))))

let blocked_tell_released_by_stop () =
  run (fun _ ->
      let gate, release = Eio.Promise.create () in
      Eio.Switch.run (fun outer ->
          let returned = ref false and asked = ref None in
          (* the handler crashes with the mailbox full and a teller blocked behind it *)
          ignore
            (Scope.run (fun sw ->
                 let actor = Actor.create ~capacity:1 ~sw ~init:0 ~handle () in
                 Actor.tell actor (Slow_crash (gate, Boom "crash"));
                 yields 2;
                 Eio.Fiber.fork ~sw:outer (fun () -> asked := Some (Actor.ask actor Get));
                 yields 2;
                 Eio.Fiber.fork ~sw:outer (fun () ->
                     Actor.tell actor (Add 1);
                     returned := true);
                 yields 2;
                 check_bool "the teller is blocked while the actor is alive" false
                   !returned;
                 Eio.Promise.resolve release ();
                 yields 5;
                 Ok ()));
          yields 5;
          check_bool "a teller blocked on a full mailbox is released when the actor stops"
            true !returned;
          check_bool "and the message queued before it is answered Actor_stopped" true
            (!asked = Some (Error `Actor_stopped))))

(* ---- nactor-tc19: ask with a timeout --------------------------------------------------- *)

let ask_timeout () =
  run (fun clock ->
      Eio.Switch.run (fun sw ->
          let gate, release = Eio.Promise.create () in
          let actor = Actor.create ~sw ~init:0 ~handle () in
          let start = Eio.Time.now clock in
          let reply = Actor.ask ~timeout:(clock, Duration.ms 50) actor (Slow (5, gate)) in
          check_bool "the wait is bounded" true (reply = Error `Timeout);
          Alcotest.(check (float 0.00001))
            "virtual time" 0.05
            (Eio.Time.now clock -. start);
          Eio.Promise.resolve release ();
          check_bool "the actor is undisturbed: the message is still handled" true
            (Actor.ask actor Get = Ok 5);
          check_bool "a fast reply beats the deadline" true
            (Actor.ask ~timeout:(clock, Duration.ms 50) actor (Add 1) = Ok 6);
          check_int "the deadline left no timer behind" 6 (Actor.state actor)))

(* ---- nactor-e0l5 nactor-oxao: stop with the switch ------------------------------------- *)

let stops_with_switch () =
  run (fun _ ->
      let stopped_with = ref [] and released = ref [] in
      let answers = ref [] in
      let gate, release = Eio.Promise.create () in
      let actor = ref None in
      Eio.Switch.run (fun outer ->
          Eio.Fiber.fork ~sw:outer (fun () ->
              yields 4;
              Eio.Promise.resolve release ());
          let subscription =
            Eio.Switch.run (fun sw ->
                Eio.Switch.on_release sw (fun () -> released := "release" :: !released);
                let a =
                  Actor.create
                    ~on_stop:(fun state ->
                      released := "on_stop" :: !released;
                      stopped_with := state :: !stopped_with)
                    ~sw ~init:0 ~handle ()
                in
                actor := Some a;
                let subscription = Actor.changes a in
                (* a handler in flight when the body ends finishes; the ones queued behind
                   it are answered Actor_stopped *)
                List.iter
                  (fun (i, msg) ->
                    Eio.Fiber.fork ~sw:outer (fun () ->
                        let reply = Actor.ask a msg in
                        answers := (i, reply) :: !answers))
                  [ (1, Slow (1, gate)); (2, Add 2); (3, Add 3) ];
                Eio.Fiber.yield ();
                subscription)
          in
          yields 3;
          Alcotest.(check (list int))
            "on_stop ran once, with the final state" [ 1 ] !stopped_with;
          Alcotest.(check (list string))
            "on_stop before the switch's own releases" [ "release"; "on_stop" ] !released;
          let answer i = List.assoc i !answers in
          check_bool "in flight finished" true (answer 1 = Ok 1);
          check_bool "pending are Actor_stopped" true
            (answer 2 = Error `Actor_stopped && answer 3 = Error `Actor_stopped);
          let delivered = Actor.Changes.next subscription in
          let ended = Actor.Changes.next subscription in
          Alcotest.(check (list (option int)))
            "changes delivered what was produced, then ended" [ Some 1; None ]
            [ delivered; ended ];
          match !actor with
          | Some a ->
              check_bool "the mailbox is closed" true
                (Actor.ask a Get = Error `Actor_stopped)
          | None -> assert false))

let on_stop_after_crash () =
  run (fun _ ->
      let finals = ref [] in
      let exit =
        Scope.run (fun sw ->
            let actor =
              Actor.create
                ~on_stop:(fun state -> finals := state :: !finals)
                ~sw ~init:0 ~handle ()
            in
            ((* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
             let _ask_result = Actor.ask actor (Add 4) in
             ());
            Actor.tell actor (Crash (Boom "x"));
            yields 5;
            Ok ())
      in
      check_bool "the crash is the scope's outcome" true
        (match exit with Exit.Failure (Cause.Die (Boom "x", _)) -> true | _ -> false);
      Alcotest.(check (list int))
        "on_stop ran once, with the last good state" [ 4 ] !finals;
      (* a failing on_stop is loud too, alongside a crash *)
      let exit =
        Scope.run (fun sw ->
            let actor =
              Actor.create ~on_stop:(fun _ -> raise (Boom "stop")) ~sw ~init:0 ~handle ()
            in
            ((* ^nlint-hxar: The ask synchronizes actor startup; the scope-cause assertion checks the failing on_stop hook rather than the reply. *)
             let _ready_ask_result = Actor.ask actor Get in
             ());
            Ok ())
      in
      (* the switch was ending normally, so Eio's own stop reason is the primary cause and
         on_stop's exception rides with it: loud, never swallowed *)
      let rec mentions_stop = function
        | Cause.Die (Boom "stop", _) -> true
        | Cause.Suppressed { primary; finalizer } ->
            mentions_stop primary || mentions_stop finalizer
        | Cause.Concurrent causes -> List.exists mentions_stop causes
        | Cause.Finalizer cause -> mentions_stop cause
        | _ -> false
      in
      match exit with
      | Exit.Failure cause ->
          check_bool "a raising on_stop fails the switch" true (mentions_stop cause)
      | Exit.Success () -> Alcotest.fail "a raising on_stop was swallowed")

let on_stop_may_suspend () =
  run (fun clock ->
      let persisted = ref None in
      Eio.Switch.run (fun sw ->
          let actor =
            Actor.create
              ~on_stop:(fun state ->
                Eio.Time.sleep clock 1.;
                persisted := Some state)
              ~sw ~init:0 ~handle ()
          in
          (* ^nlint-hxar: The ask drives the scripted actor; the existing state, stream or shutdown assertions check its effect rather than its reply. *)
          let _ask_result = Actor.ask actor (Add 7) in
          ());
      check_bool "on_stop is protected from the cancellation that stops the actor" true
        (!persisted = Some 7))

let tests =
  [
    ( "Actor nactor-agcr nactor-jhl2 nactor-mb6v nactor-7qi7 nactor-pxfz nactor-6z3i \
       nactor-l87k nactor-512k nactor-tc19 nactor-e0l5 nactor-oxao",
      [
        Alcotest.test_case "nactor-agcr nactor-jhl2 ask and tell" `Quick ask_and_tell;
        Alcotest.test_case "nactor-mb6v arrival order, one at a time" `Quick ordering;
        Alcotest.test_case "nactor-7qi7 Error leaves the state" `Quick error_leaves_state;
        Alcotest.test_case "nactor-pxfz handler exception ends actor and switch" `Quick
          exception_ends_actor;
        Alcotest.test_case "nactor-pxfz the in-flight ask is answered" `Quick
          in_flight_ask_on_crash;
        Alcotest.test_case "nactor-pxfz nactor-e0l5 ask after stop" `Quick ask_after_stop;
        Alcotest.test_case "nactor-6z3i changes and overflow" `Quick changes_stream;
        Alcotest.test_case "nactor-6z3i nactor-e0l5 changes end with the actor" `Quick
          changes_end_with_actor;
        Alcotest.test_case "nactor-l87k state snapshot" `Quick state_snapshot;
        Alcotest.test_case "nactor-512k backpressure" `Quick backpressure;
        Alcotest.test_case "nactor-512k nactor-e0l5 stop releases a blocked tell" `Quick
          blocked_tell_released_by_stop;
        Alcotest.test_case "nactor-tc19 ask timeout" `Quick ask_timeout;
        Alcotest.test_case "nactor-e0l5 nactor-oxao stop with the switch" `Quick
          stops_with_switch;
        Alcotest.test_case "nactor-oxao nactor-pxfz on_stop after a crash" `Quick
          on_stop_after_crash;
        Alcotest.test_case "nactor-oxao on_stop may suspend" `Quick on_stop_may_suspend;
      ] );
  ]
