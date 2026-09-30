(* ^nstress-ttto. Libraries: stress_support, ox, eio, eio_main.
   Single-domain cancellation storms; every handler suspension is bounded or released
   by a finally hook. The whole executable has a 50-second watchdog. *)
open Ox

let require condition fmt =
  Printf.ksprintf (fun message -> if not condition then failwith message) fmt

let yields n =
  for _ = 1 to n do
    Eio.Fiber.yield ()
  done

type interruption = Keep | Cancel of int | Deadline of float
type 'a outcome = Returned of 'a | Cancelled | Expired

exception Caller_cancelled

(* Controllers belong to the enclosing switch, not to the cancelled caller. Do not
   cancel a context after its caller has finished; do not swallow watchdog cancellation. *)
let attempt ?(before_cancel = fun () -> ()) ~sw ~clock interruption f =
  match interruption with
  | Keep -> Returned (f ())
  | Deadline seconds -> (
      match Eio.Time.with_timeout clock seconds (fun () -> Ok (f ())) with
      | Ok value -> Returned value
      | Error `Timeout -> Expired)
  | Cancel delay -> (
      let active = ref true in
      try
        Eio.Cancel.sub (fun cc ->
            Eio.Fiber.fork ~sw (fun () ->
                yields delay;
                before_cancel ();
                if !active then Eio.Cancel.cancel cc Caller_cancelled);
            Fun.protect ~finally:(fun () -> active := false) (fun () -> Returned (f ())))
      with Eio.Cancel.Cancelled Caller_cancelled -> Cancelled)

let interruption rng id =
  match id mod 5 with
  | 0 | 4 -> Keep
  | 1 | 2 -> Cancel (Random.State.int rng 20)
  | _ -> Deadline (float_of_int (Random.State.int rng 3) *. 0.0001)

type message = Add of int | Barrier | Hold of unit Eio.Promise.t * unit Eio.Promise.u

type ledger = {
  visits : int array;
  tickets : int option array;
  reject : bool array;
  delays : int array;
  mutable applied : int;
  mutable handling : bool;
}

let ledger rng n =
  {
    visits = Array.make n 0;
    tickets = Array.make n None;
    reject = Array.init n (fun id -> id mod 13 = 12);
    delays = Array.init n (fun _ -> Random.State.int rng 5);
    applied = 0;
    handling = false;
  }

let handle ~clock book state message =
  require (not book.handling) "Actor handlers overlap";
  require (state = book.applied) "Actor state %d differs from applied count %d" state
    book.applied;
  book.handling <- true;
  Fun.protect
    ~finally:(fun () -> book.handling <- false)
    (fun () ->
      match message with
      | Barrier -> Ok (state, state)
      | Hold (release, entered) ->
          Eio.Promise.resolve entered ();
          Eio.Promise.await release;
          Ok (state, state)
      | Add id ->
          book.visits.(id) <- book.visits.(id) + 1;
          require (book.visits.(id) = 1) "Actor applied ask %d more than once" id;
          yields book.delays.(id);
          if id mod 32 = 0 then Eio.Time.sleep clock 0.0005;
          if book.reject.(id) then Error `Rejected
          else (
            book.applied <- book.applied + 1;
            book.tickets.(id) <- Some book.applied;
            Ok (state + 1, book.applied)))

let check_actor book outcomes ~stopped =
  let answered = ref 0 and cancelled = ref 0 and timed_out = ref 0 and ended = ref 0 in
  Array.iteri
    (fun id outcome ->
      match outcome with
      | None -> failwith (Printf.sprintf "Actor ask %d never settled" id)
      | Some (Returned (Ok ticket)) ->
          incr answered;
          require
            (book.tickets.(id) = Some ticket)
            "Actor ask %d has wrong reply %d" id ticket
      | Some (Returned (Error `Rejected)) ->
          incr answered;
          require
            (book.reject.(id) && book.visits.(id) = 1 && book.tickets.(id) = None)
            "Actor rejected ask %d changed state or vanished" id
      | Some (Returned (Error `Timeout)) ->
          incr timed_out;
          if not stopped then
            require (book.visits.(id) = 1) "Actor timeout lost queued ask %d" id
      | Some (Returned (Error `Actor_stopped)) ->
          incr ended;
          require stopped "Actor stopped during live storm"
      | Some Cancelled -> incr cancelled
      | Some Expired -> incr timed_out)
    outcomes;
  let counted =
    Array.fold_left (fun n -> function Some _ -> n + 1 | None -> n) 0 book.tickets
  in
  require (counted = book.applied) "Actor ledger count %d differs from state %d" counted
    book.applied;
  (!answered, !cancelled, !timed_out, !ended)

let actor_storm ~clock rng capacity =
  let n = 2048 in
  let book = ledger rng n in
  let outcomes = Array.make n None in
  let plans = Array.init n (fun id -> (interruption rng id, Random.State.int rng 5)) in
  let stopped = ref [] in
  Eio.Switch.run (fun sw ->
      let actor =
        Actor.create ~sw ~capacity ~init:0 ~handle:(handle ~clock book)
          ~on_stop:(fun state -> stopped := state :: !stopped)
          ()
      in
      for batch = 0 to (n / 64) - 1 do
        Eio.Switch.run (fun callers ->
            for id = batch * 64 to ((batch + 1) * 64) - 1 do
              Eio.Fiber.fork ~sw:callers (fun () ->
                  let cancel, before = plans.(id) in
                  outcomes.(id) <-
                    Some
                      (attempt ~sw:callers ~clock cancel (fun () ->
                           yields before;
                           Eio.Fiber.check ();
                           if id mod 5 = 4 then
                             Actor.ask
                               ~timeout:(clock, Duration.ms (id mod 2))
                               actor (Add id)
                           else Actor.ask actor (Add id))))
            done)
      done;
      let final = Actor.ask actor Barrier in
      require (final = Ok book.applied) "Actor barrier has wrong state";
      require (Actor.state actor = book.applied) "Actor final state has wrong count";
      let answered, cancelled, timed_out, _ = check_actor book outcomes ~stopped:false in
      require
        (answered > 0 && cancelled > 0 && timed_out > 0)
        "Actor storm did not exercise replies, cancellation and timeouts";
      Printf.printf
        "actor capacity=%d asks=%d answered=%d cancelled=%d timed_out=%d applied=%d\n%!"
        capacity n answered cancelled timed_out book.applied);
  require (!stopped = [ book.applied ]) "Actor finalizer missed final state or ran twice"

(* All these asks are certainly queued: the mailbox fits the entire burst and the
   first handler is held. Cancellation must abandon replies, never queued messages. *)
let actor_queued_cancellation ~clock rng =
  let n = 512 in
  let book = ledger rng n in
  let delays = Array.init n (fun _ -> 1 + Random.State.int rng 20) in
  let outcomes = Array.make n None in
  Eio.Switch.run (fun sw ->
      let actor = Actor.create ~sw ~capacity:n ~init:0 ~handle:(handle ~clock book) () in
      let gate, release = Eio.Promise.create () in
      let entered, mark_entered = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          require
            (Actor.ask actor (Hold (gate, mark_entered)) = Ok 0)
            "Held ask lost reply");
      Eio.Promise.await entered;
      Fun.protect
        ~finally:(fun () -> Eio.Promise.resolve release ())
        (fun () ->
          Eio.Switch.run (fun callers ->
              for id = 0 to n - 1 do
                Eio.Fiber.fork ~sw:callers (fun () ->
                    outcomes.(id) <-
                      Some
                        (if id mod 2 = 0 then
                           attempt ~sw:callers ~clock
                             (Cancel delays.(id))
                             (fun () -> Actor.ask actor (Add id))
                         else
                           Returned
                             (Actor.ask ~timeout:(clock, Duration.zero) actor (Add id))))
              done);
          Array.iteri
            (fun id outcome ->
              require
                (book.visits.(id) = 0)
                "Queued cancellation ask %d ran before release" id;
              require
                (outcome = Some Cancelled || outcome = Some (Returned (Error `Timeout)))
                "Queued cancellation ask %d did not observe interruption" id)
            outcomes);
      let final = Actor.ask actor Barrier in
      require (final = Ok book.applied) "Queued-cancel barrier failed";
      Array.iteri
        (fun id count -> require (count = 1) "Queued ask %d was lost" id)
        book.visits;
      ignore (check_actor book outcomes ~stopped:false);
      Printf.printf "actor queued-cancel asks=%d applied=%d\n%!" n book.applied)

(* A handshake cancels an asker while its handler is definitely running. Even then
   the protected invocation must finish and commit exactly once after release. *)
let actor_inflight_cancellation ~clock rng =
  let n = 128 in
  let book = ledger rng n in
  let signals = Array.init n (fun _ -> Eio.Promise.create ()) in
  let gates = Array.init n (fun _ -> Eio.Promise.create ()) in
  let delays = Array.init n (fun _ -> Random.State.int rng 20) in
  let outcomes = Array.make n None in
  Eio.Switch.run (fun sw ->
      let handle state message =
        (match message with
        | Add id ->
            Eio.Promise.resolve (snd signals.(id)) ();
            Eio.Promise.await (fst gates.(id))
        | Barrier | Hold _ -> ());
        handle ~clock book state message
      in
      let actor = Actor.create ~sw ~capacity:1 ~init:0 ~handle () in
      for id = 0 to n - 1 do
        Fun.protect
          ~finally:(fun () -> Eio.Promise.resolve (snd gates.(id)) ())
          (fun () ->
            Eio.Switch.run (fun callers ->
                let result =
                  Eio.Fiber.fork_promise ~sw:callers (fun () ->
                      attempt ~sw:callers ~clock
                        ~before_cancel:(fun () ->
                          Eio.Promise.await (fst signals.(id));
                          yields delays.(id))
                        (Cancel 0)
                        (fun () -> Actor.ask actor (Add id)))
                in
                let outcome = Eio.Promise.await_exn result in
                require (outcome = Cancelled)
                  "In-flight asker %d did not observe cancellation" id;
                outcomes.(id) <- Some outcome));
        let final = Actor.ask actor Barrier in
        require (final = Ok book.applied) "In-flight cancellation left inconsistent state"
      done;
      Array.iteri
        (fun id visits -> require (visits = 1) "In-flight ask %d was lost" id)
        book.visits;
      ignore (check_actor book outcomes ~stopped:false);
      require (Actor.state actor = book.applied) "In-flight actor state differs";
      Printf.printf "actor in-flight-cancel asks=%d applied=%d\n%!" n book.applied)

(* Askers outlive the actor's own switch, so actor shutdown must settle pending replies
   and wake senders blocked on the full mailbox, rather than cancelling them all. *)
let actor_stop_storm ~clock rng =
  let n = 512 in
  let book = ledger rng n in
  let plans = Array.init n (fun id -> interruption rng id) in
  let outcomes = Array.make n None in
  let stopped = ref [] in
  Eio.Switch.run (fun sw ->
      let ready, publish = Eio.Promise.create () in
      let gate, release = Eio.Promise.create () in
      let owner =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Switch.run (fun actor_sw ->
                let actor =
                  Actor.create ~sw:actor_sw ~capacity:8 ~init:0
                    ~handle:(handle ~clock book)
                    ~on_stop:(fun state -> stopped := state :: !stopped)
                    ()
                in
                Eio.Promise.resolve publish actor;
                Eio.Promise.await gate))
      in
      let actor = Eio.Promise.await ready in
      Fun.protect
        ~finally:(fun () -> Eio.Promise.resolve release ())
        (fun () ->
          for id = 0 to n - 1 do
            Eio.Fiber.fork ~sw (fun () ->
                outcomes.(id) <-
                  Some
                    (attempt ~sw ~clock plans.(id) (fun () -> Actor.ask actor (Add id))))
          done;
          yields (1 + Random.State.int rng 20));
      Eio.Promise.await_exn owner);
  let answered, cancelled, timed_out, ended = check_actor book outcomes ~stopped:true in
  require (ended > 0) "Actor shutdown had no pending asks";
  require (!stopped = [ book.applied ]) "Stopped actor finalizer count/state differs";
  Printf.printf
    "actor stop asks=%d answered=%d cancelled=%d timed_out=%d stopped=%d applied=%d\n%!" n
    answered cancelled timed_out ended book.applied

let channel_blocked_cancellation ~clock rng capacity =
  let channel = Channel.create ~capacity () in
  for id = 0 to capacity - 1 do
    require (Channel.send channel id = Ok ()) "Channel preload failed"
  done;
  let blocked operation =
    let plans =
      Array.init 128 (fun id ->
          if id mod 2 = 0 then Cancel (1 + Random.State.int rng 10) else Deadline 0.0001)
    in
    Eio.Switch.run (fun sw ->
        Array.iteri
          (fun id plan ->
            Eio.Fiber.fork ~sw (fun () ->
                match attempt ~sw ~clock plan (fun () -> operation id) with
                | Cancelled | Expired -> ()
                | Returned _ ->
                    failwith "Blocked Channel operation unexpectedly completed"))
          plans)
  in
  blocked (fun id -> Channel.send channel (capacity + id));
  for id = 0 to capacity - 1 do
    require
      (Channel.receive channel = Ok id)
      "Cancelled send lost/duplicated existing item %d" id
  done;
  require
    (Channel.try_receive channel = Error `Empty)
    "Cancelled send left a phantom item";
  blocked (fun _ -> Channel.receive channel);
  require (Channel.send channel 12345 = Ok ()) "Channel marker send failed";
  require (Channel.receive channel = Ok 12345) "Cancelled receiver consumed a later item";
  Channel.done_ channel;
  require (Channel.receive channel = Error `Done) "Closed Channel did not finish"

let channel_storm ~clock rng capacity =
  let n = 4096 in
  let channel = Channel.create ~capacity () in
  let sent = Array.make n 0 and received = Array.make n 0 in
  let plans = Array.init n (fun id -> (interruption rng id, Random.State.int rng 4)) in
  let receive_plans =
    Array.init 8 (fun _ ->
        Array.init 256 (fun id -> (interruption rng id, Random.State.int rng 5)))
  in
  let send_cancelled = ref 0 and recv_cancelled = ref 0 in
  let send_timeouts = ref 0 and recv_timeouts = ref 0 in
  Eio.Switch.run (fun sw ->
      for worker = 0 to 7 do
        Eio.Fiber.fork ~sw (fun () ->
            let rec loop iteration =
              let plan, delay = receive_plans.(worker).(iteration mod 256) in
              let result =
                attempt ~sw ~clock plan (fun () ->
                    yields delay;
                    Eio.Fiber.check ();
                    match Channel.receive channel with
                    | Ok id ->
                        require (id >= 0 && id < n) "Channel received unknown item %d" id;
                        received.(id) <- received.(id) + 1;
                        require (received.(id) = 1) "Channel duplicated item %d" id;
                        Ok id
                    | Error `Done -> Error `Done
                    | Error (`Error _) -> failwith "Channel unexpectedly failed")
              in
              match result with
              | Returned (Error `Done) -> ()
              | Returned (Ok _) -> loop (iteration + 1)
              | Cancelled ->
                  incr recv_cancelled;
                  loop (iteration + 1)
              | Expired ->
                  incr recv_timeouts;
                  loop (iteration + 1)
            in
            loop 0)
      done;
      Eio.Switch.run (fun producers ->
          for worker = 0 to 15 do
            Eio.Fiber.fork ~sw:producers (fun () ->
                for step = 0 to (n / 16) - 1 do
                  let id = worker + (step * 16) in
                  let send () =
                    require
                      (Channel.send channel id = Ok ())
                      "Channel closed before send %d" id;
                    (* Record immediately: a timeout race may discard the return value of a
                       completed branch. Retry only items not observed committed, not every
                       operation whose surrounding timeout expired. Receives do the same. *)
                    sent.(id) <- sent.(id) + 1;
                    require (sent.(id) = 1) "Channel item %d was sent twice" id
                  in
                  let plan, delay = plans.(id) in
                  (match
                     attempt ~sw:producers ~clock plan (fun () ->
                         yields delay;
                         Eio.Fiber.check ();
                         send ())
                   with
                  | Returned () -> ()
                  | Cancelled -> incr send_cancelled
                  | Expired -> incr send_timeouts);
                  if sent.(id) = 0 then send ()
                done)
          done);
      Channel.done_ channel);
  for id = 0 to n - 1 do
    require
      (sent.(id) = 1 && received.(id) = 1)
      "Channel capacity=%d item=%d sent=%d received=%d" capacity id sent.(id)
      received.(id)
  done;
  require
    (!send_cancelled > 0 && !recv_cancelled > 0)
    "Channel storm did not cancel both sides";
  require
    (Channel.try_receive channel = Error `Done)
    "Channel retained an extra item after close";
  Printf.printf
    "channel capacity=%d items=%d send_cancelled=%d recv_cancelled=%d send_timeouts=%d \
     recv_timeouts=%d\n\
     %!"
    capacity n !send_cancelled !recv_cancelled !send_timeouts !recv_timeouts

let () =
  let rng = Stress_support.random ~default:6060 () in
  Eio_main.run (fun env ->
      let clock = Eio.Stdenv.clock env in
      Eio.Time.with_timeout_exn clock 50.0 (fun () ->
          List.iter (actor_storm ~clock rng) [ 1; 8; 64 ];
          actor_queued_cancellation ~clock rng;
          actor_inflight_cancellation ~clock rng;
          actor_stop_storm ~clock rng;
          List.iter
            (fun capacity ->
              channel_blocked_cancellation ~clock rng capacity;
              channel_storm ~clock rng capacity)
            [ 1; 8; 64 ]));
  Printf.printf "nstress-ttto: cancellation storms passed\n%!"
