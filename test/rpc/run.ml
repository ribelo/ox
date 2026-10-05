(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
open Ox_rpc

type message = { id : int option; session : string option; value : int }

let msg ?id ?session value = { id; session; value }
let id m = m.id
let set_id m id = { m with id = Some id }
let session m = m.session

type input = Message of message | Eof | Read_error of exn

type fixture = {
  incoming : input Eio.Stream.t;
  outgoing : message Eio.Stream.t;
  mutable reader_cancelled : bool;
  mutable writes : message list;
  mutable on_write : message -> unit;
}

let fixture () =
  {
    incoming = Eio.Stream.create 100;
    outgoing = Eio.Stream.create 100;
    reader_cancelled = false;
    writes = [];
    on_write = (fun _ -> ());
  }

let push f m = Eio.Stream.add f.incoming (Message m)

let make ~sw ~clock ?(max_notifications = 1024) f =
  Correlator.create ~sw ~clock ~max_notifications
    ~read:(fun () ->
      try
        match Eio.Stream.take f.incoming with
        | Message m -> Some m
        | Eof -> None
        | Read_error exn -> raise exn
      with Eio.Cancel.Cancelled _ as exn ->
        f.reader_cancelled <- true;
        raise exn)
    ~write:(fun m ->
      Eio.Stream.add f.outgoing m;
      f.writes <- f.writes @ [ m ];
      f.on_write m)
    ~id ~set_id ~session ()

let wait_until condition =
  let rec loop remaining =
    if condition () then ()
    else if remaining = 0 then Alcotest.fail "condition never became true"
    else (
      Eio.Fiber.yield ();
      loop (remaining - 1))
  in
  loop 1000

let take_message q =
  match Eio.Stream.take q with
  | Correlator.Message m -> m
  | Correlator.Closed _ -> Alcotest.fail "expected notification before closure"

let check_reply expected = function
  | Ok m -> Alcotest.(check int) "reply" expected m.value
  | Error _ -> Alcotest.fail "expected matching reply"

(* nrpc-wkrp nrpc-pqed nrpc-3ikx nrpc-acml nrpc-d96a *)
let routing () =
  Ox_test.run (fun env sw ->
      let f = fixture () in
      let c = make ~sw ~clock:env#clock f in
      let a = Eio.Fiber.fork_promise ~sw (fun () -> Correlator.call c (msg 1)) in
      let b =
        Eio.Fiber.fork_promise ~sw (fun () -> Correlator.call c (msg ~session:"B" 2))
      in
      wait_until (fun () -> List.length f.writes = 2);
      let a_id =
        match
          (match List.find_opt (fun m -> m.value = 1) f.writes with
          | Some value -> value
          | None -> Alcotest.fail "missing rpc/run fixture: matching record")
            .id
        with
        | Some value -> value
        | None -> Alcotest.fail "missing RPC request message ID fixture"
      in
      let b_id =
        match
          (match List.find_opt (fun m -> m.value = 2) f.writes with
          | Some value -> value
          | None -> Alcotest.fail "missing rpc/run fixture: matching record")
            .id
        with
        | Some value -> value
        | None -> Alcotest.fail "missing RPC request message ID fixture"
      in
      Alcotest.(check bool) "distinct IDs" true (a_id <> b_id);
      push f (msg 10);
      push f (msg ~id:a_id ~session:"B" 11);
      push f (msg ~id:b_id ~session:"B" 22);
      push f (msg ~id:a_id 21);
      push f (msg ~id:a_id 12);
      check_reply 21 (Eio.Promise.await_exn a);
      check_reply 22 (Eio.Promise.await_exn b);
      wait_until (fun () -> (Correlator.stats c).buffered_notifications = 3);
      let q = Correlator.notifications c in
      Alcotest.(check (list int))
        "unmatched FIFO" [ 10; 11; 12 ]
        (List.init 3 (fun _ -> (take_message q).value));
      Alcotest.(check int) "no pending requests" 0 (Correlator.stats c).pending;
      Correlator.close c)

(* nrpc-acml nrpc-d96a: slow consumers lose oldest, counted *)
let overflow () =
  Ox_test.run (fun env sw ->
      let f = fixture () in
      let c = make ~sw ~clock:env#clock ~max_notifications:2 f in
      List.iter (fun n -> push f (msg n)) [ 1; 2; 3; 4 ];
      wait_until (fun () -> (Correlator.stats c).dropped_notifications = 2);
      Alcotest.(check int) "bounded" 2 (Correlator.stats c).buffered_notifications;
      let q = Correlator.notifications c in
      Correlator.close c;
      Alcotest.(check int)
        "terminal evicts oldest when full" 3 (Correlator.stats c).dropped_notifications;
      Alcotest.(check int) "newest message retained" 4 (take_message q).value;
      (match Eio.Stream.take q with
      | Correlator.Closed `Closed -> ()
      | _ -> Alcotest.fail "nlimit-ruzp terminal must survive overflow");
      Alcotest.(check bool)
        "terminal is last" true
        (Option.is_none (Eio.Stream.take_nonblocking q)))

(* nrpc-amni nrpc-d96a: mock time and late reply *)
let deadline () =
  Ox_test.run (fun env sw ->
      let f = fixture () in
      let c = make ~sw ~clock:env#clock f in
      let call =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Correlator.call c ~deadline:(Ox.Duration.ms 10) (msg 1))
      in
      wait_until (fun () -> List.length f.writes = 1);
      Ox_test.advance env#clock (Ox.Duration.ms 10);
      (match Eio.Promise.await_exn call with
      | Error `Timeout -> ()
      | _ -> Alcotest.fail "expected timeout");
      Alcotest.(check int) "slot dropped" 0 (Correlator.stats c).pending;
      push f
        (msg
           ~id:
             (match
                (match f.writes with
                | head :: _ -> head
                | [] -> Alcotest.fail "missing rpc/run fixture: f.writes")
                  .id
              with
             | Some value -> value
             | None -> Alcotest.fail "missing RPC request message ID fixture")
           99);
      wait_until (fun () -> (Correlator.stats c).buffered_notifications = 1);
      Alcotest.(check int)
        "late reply is notification" 99 (take_message (Correlator.notifications c)).value;
      Correlator.close c)

(* nrpc-1glx nrpc-d96a: interruption, no fabricated response *)
let cancellation () =
  Ox_test.run (fun env sw ->
      let f = fixture () in
      let c = make ~sw ~clock:env#clock f in
      let cancel = ref None in
      let outcome =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: A normal reply makes this cancellation probe false; the existing interruption, slot and write assertions decide the outcome. *)
                   let _call_result =
                     Correlator.call c (msg 1)
                       [@@ox.allow
                         "ox-discarded-result: correlator cancellation probe rejects a \
                          normal reply and checks interruption slot release and writes"]
                   in
                   ());
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      wait_until (fun () -> (Correlator.stats c).pending = 1 && !cancel <> None);
      Eio.Cancel.cancel
        (match !cancel with
        | Some value -> value
        | None -> Alcotest.fail "missing rpc/run fixture: !cancel")
        (Failure "test cancelled request");
      Alcotest.(check bool) "interruption propagated" true (Eio.Promise.await_exn outcome);
      Alcotest.(check int) "cancelled slot removed" 0 (Correlator.stats c).pending;
      push f
        (msg
           ~id:
             (match
                (match f.writes with
                | head :: _ -> head
                | [] -> Alcotest.fail "missing rpc/run fixture: f.writes")
                  .id
              with
             | Some value -> value
             | None -> Alcotest.fail "missing RPC request message ID fixture")
           12);
      wait_until (fun () -> (Correlator.stats c).buffered_notifications = 1);
      Alcotest.(check int)
        "late reply" 12 (take_message (Correlator.notifications c)).value;
      Correlator.close c)

(* nrpc-1glx nrpc-vnce: cancelling a call while its frame is being written waits for the
   whole frame; a half-written frame would corrupt every later message *)
let cancellation_mid_write () =
  Ox_test.run (fun env sw ->
      let f = fixture () in
      let started = ref false and finished = ref false in
      f.on_write <-
        (fun _ ->
          started := true;
          (* a write that suspends part-way, as a large frame on a pipe does *)
          Eio.Fiber.yield ();
          Eio.Fiber.yield ();
          finished := true);
      let c = make ~sw ~clock:env#clock f in
      let cancel = ref None in
      let outcome =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: A normal reply makes this cancellation probe false; the existing interruption, slot and write assertions decide the outcome. *)
                   let _call_result =
                     Correlator.call c (msg 1)
                       [@@ox.allow
                         "ox-discarded-result: correlator cancellation probe rejects a \
                          normal reply and checks interruption slot release and writes"]
                   in
                   ());
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      wait_until (fun () -> !started);
      Eio.Cancel.cancel
        (match !cancel with
        | Some value -> value
        | None -> Alcotest.fail "missing rpc/run fixture: !cancel")
        (Failure "cancelled mid-write");
      Alcotest.(check bool) "interruption propagated" true (Eio.Promise.await_exn outcome);
      Alcotest.(check bool) "frame written whole" true !finished;
      Correlator.close c)

(* nrpc-hjv6 nrpc-lf9n nrpc-wkrp nrpc-d96a *)
let closures () =
  List.iter
    (fun terminate ->
      Ox_test.run (fun env sw ->
          let f = fixture () in
          let c = make ~sw ~clock:env#clock f in
          let a = Eio.Fiber.fork_promise ~sw (fun () -> Correlator.call c (msg 1)) in
          let b = Eio.Fiber.fork_promise ~sw (fun () -> Correlator.call c (msg 2)) in
          wait_until (fun () -> (Correlator.stats c).pending = 2);
          let reason =
            match terminate with
            | `Eof ->
                Eio.Stream.add f.incoming Eof;
                `Eof
            | `Read_failed ->
                Eio.Stream.add f.incoming (Read_error (Failure "broken"));
                `Read_failed
            | `Closed ->
                Correlator.close c;
                `Closed
          in
          let expect = function
            | Error (`Transport_closed `Eof) when reason = `Eof -> ()
            | Error (`Transport_closed (`Read_failed exn))
              when reason = `Read_failed
                   && match exn with Failure _ -> true | _ -> false ->
                ()
            | Error (`Transport_closed `Closed) when reason = `Closed -> ()
            | _ -> Alcotest.fail "wrong close reason"
          in
          expect (Eio.Promise.await_exn a);
          expect (Eio.Promise.await_exn b);
          Alcotest.(check int) "all pending settled" 0 (Correlator.stats c).pending;
          expect (Correlator.call c (msg 3));
          Correlator.close c;
          (match Eio.Stream.take (Correlator.notifications c) with
          | Correlator.Closed `Eof when reason = `Eof -> ()
          | Correlator.Closed (`Read_failed (Failure _)) when reason = `Read_failed -> ()
          | Correlator.Closed `Closed when reason = `Closed -> ()
          | _ -> Alcotest.fail "nlimit-ruzp: wrong terminal reason");
          Alcotest.(check bool)
            "nlimit-ruzp terminal exactly once" true
            (Option.is_none (Eio.Stream.take_nonblocking (Correlator.notifications c)));
          if reason = `Closed then
            Alcotest.(check bool) "reader joined" true f.reader_cancelled;
          Correlator.close c))
    [ `Eof; `Read_failed; `Closed ]

(* nrpc-vnce nrpc-pqed: write failure is local and never retried *)
let write_failure () =
  Ox_test.run (fun env sw ->
      let f = fixture () in
      let c = make ~sw ~clock:env#clock f in
      f.on_write <- (fun _ -> failwith "rejected");
      (match Correlator.call c (msg 1) with
      | Error (`Write_failed exn) when match exn with Failure _ -> true | _ -> false ->
          ()
      | _ -> Alcotest.fail "expected local write failure");
      Alcotest.(check int) "no retry" 1 (List.length f.writes);
      Alcotest.(check int) "slot removed" 0 (Correlator.stats c).pending;
      f.on_write <-
        (fun sent ->
          push f
            (msg
               ~id:
                 (match sent.id with
                 | Some value -> value
                 | None -> Alcotest.fail "missing rpc/run fixture: sent.id")
               42));
      check_reply 42 (Correlator.call c (msg 2));
      Alcotest.(check (list int))
        "fresh id after failure" [ 1; 2 ]
        (List.map
           (fun m ->
             match m.id with
             | Some value -> value
             | None -> Alcotest.fail "missing rpc/run fixture: m.id")
           f.writes);
      Correlator.close c)

let () =
  Alcotest.run "ox_rpc"
    [
      ( "correlator",
        [
          Alcotest.test_case "nrpc-wkrp nrpc-pqed nrpc-3ikx nrpc-acml nrpc-d96a routing"
            `Quick routing;
          Alcotest.test_case "nrpc-acml nrpc-d96a overflow" `Quick overflow;
          Alcotest.test_case "nrpc-amni nrpc-d96a deadline" `Quick deadline;
          Alcotest.test_case "nrpc-1glx nrpc-d96a cancellation" `Quick cancellation;
          Alcotest.test_case "nrpc-1glx nrpc-vnce cancellation mid-write" `Quick
            cancellation_mid_write;
          Alcotest.test_case "nrpc-hjv6 nrpc-lf9n nrpc-d96a closures" `Quick closures;
          Alcotest.test_case "nrpc-vnce nrpc-pqed write failure" `Quick write_failure;
        ] );
    ]
