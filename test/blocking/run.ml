open Eta_blocking

let pool ~sw ?(threads = 1) ?(queued = 1) ?(policy = Pool.Drain) () =
  Pool.create ~sw ~name:"test"
    { max_threads = threads; max_queued = queued; shutdown_policy = policy }

let within f =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 5. (fun () ->
          Eio.Switch.run (fun sw -> f env sw)))

let wait_until clock predicate =
  let rec loop () =
    if not (predicate ()) then (
      Eio.Time.sleep clock 0.001;
      loop ())
  in
  loop ()

let gate () = Semaphore.Counting.make 0
let release = Semaphore.Counting.release
let wait = Semaphore.Counting.acquire

(* nblock-a7q2 nblock-f4kx: bounded workers, typed errors, and overload. *)
let typed_and_bounded () =
  within (fun env sw ->
      let p = pool ~sw () in
      Alcotest.(
        check (result int (of_pp (fun fmt _ -> Format.pp_print_string fmt "closed"))))
        "value" (Ok 7)
        (run ~pool:p (fun () -> 7));
      (match run_result ~pool:p (fun () -> Error `Native) with
      | Error (`Callback `Native) -> ()
      | _ -> Alcotest.fail "typed callback error lost");
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
      let first =
        Eio.Fiber.fork_promise ~sw (fun () ->
            run ~pool:p (fun () ->
                Eio.Semaphore.release started;
                wait permit;
                8))
      in
      Eio.Semaphore.acquire started;
      Alcotest.(check int) "physical slot held" 1 (Pool.stats p).active;
      (match try_run ~pool:p (fun () -> failwith "must not start") with
      | Not_run Saturated -> ()
      | _ -> Alcotest.fail "expected saturation");
      let second = Eio.Fiber.fork_promise ~sw (fun () -> run ~pool:p (fun () -> 9)) in
      wait_until env#clock (fun () -> (Pool.stats p).queued = 1);
      Alcotest.(check int) "bounded admitted queue" 1 (Pool.stats p).queued;
      release permit;
      Alcotest.(
        check (result int (of_pp (fun fmt _ -> Format.pp_print_string fmt "closed"))))
        "first completion" (Ok 8) (Eio.Promise.await_exn first);
      (match Eio.Promise.await_exn second with
      | Ok 9 -> ()
      | _ -> Alcotest.fail "queued run");
      Pool.shutdown p;
      (match try_run ~pool:p (fun () -> 0) with
      | Not_run Shutting_down -> ()
      | _ -> Alcotest.fail "expected closed pool");
      match run_result ~pool:p (fun () -> Ok 0) with
      | Error `Shutting_down -> ()
      | _ -> Alcotest.fail "expected typed shutdown")

(* nblock-j9wr nblock-v8ze nblock-p5dm: timeout releases caller, not worker. *)
let timeout_retains_slot () =
  within (fun env sw ->
      let p = pool ~sw () in
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
      let hooks = Atomic.make 0 in
      let result =
        run_result_timeout ~pool:p ~clock:env#clock ~timeout:(Eta.Duration.ms 100)
          ~on_timeout:`Slow
          ~on_cancel:(fun () -> ignore (Atomic.fetch_and_add hooks 1))
          (fun () ->
            Eio.Semaphore.release started;
            wait permit;
            Ok 17)
      in
      (match result with Error (`Timed_out `Slow) -> () | _ -> Alcotest.fail "timeout");
      Eio.Semaphore.acquire started;
      Alcotest.(check int) "hook called once" 1 (Atomic.get hooks);
      Alcotest.(check int) "active native work" 1 (Pool.stats p).active;
      (match try_run ~pool:p (fun () -> 0) with
      | Not_run Saturated -> ()
      | _ -> Alcotest.fail "slot released too early");
      release permit;
      Pool.shutdown p;
      Alcotest.(check int) "drain waited" 0 (Pool.stats p).active;
      Alcotest.(check int) "completed physically" 1 (Pool.stats p).completed)

(* nblock-v8ze: cancellation while queued never starts callback. *)
let queued_cancellation () =
  within (fun env sw ->
      let p = pool ~sw () in
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
      let first =
        Eio.Fiber.fork_promise ~sw (fun () ->
            run ~pool:p (fun () ->
                Eio.Semaphore.release started;
                wait permit))
      in
      Eio.Semaphore.acquire started;
      let cancel = ref None in
      let ran = Atomic.make false in
      let second =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  ignore (run ~pool:p (fun () -> Atomic.set ran true));
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      wait_until env#clock (fun () -> (Pool.stats p).queued = 1 && !cancel <> None);
      Eio.Cancel.cancel (Option.get !cancel) (Failure "test cancellation");
      Alcotest.(check bool) "queued caller released" true (Eio.Promise.await_exn second);
      Alcotest.(check int) "queue removed" 0 (Pool.stats p).queued;
      release permit;
      ignore (Eio.Promise.await_exn first);
      Pool.shutdown p;
      Alcotest.(check bool) "never started" false (Atomic.get ran))

let inc x = ignore (Atomic.fetch_and_add x 1)

(* nblock-v8ze nblock-p5dm: direct cancellation releases caller, not lease. *)
let running_cancellation () =
  within (fun _env sw ->
      let p = pool ~sw () in
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
      let cancel = ref None in
      let hooks = Atomic.make 0 in
      let caller =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  ignore
                    (run ~pool:p
                       ~on_cancel:(fun () -> inc hooks)
                       (fun () ->
                         Eio.Semaphore.release started;
                         wait permit;
                         42));
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      Eio.Semaphore.acquire started;
      Eio.Cancel.cancel (Option.get !cancel) (Failure "stop caller");
      Alcotest.(check bool)
        "caller returned before worker" true
        (Eio.Promise.await_exn caller);
      Alcotest.(check int) "hook exactly once" 1 (Atomic.get hooks);
      Alcotest.(check int) "physical slot retained" 1 (Pool.stats p).active;
      release permit;
      Pool.shutdown p;
      Alcotest.(check int) "drained on shutdown" 0 (Pool.stats p).active)

exception Native_defect

(* nblock-p5dm: callback defects remain defects, detached shutdown is explicit. *)
let defects_and_detach () =
  within (fun _env sw ->
      let p = pool ~sw ~policy:Pool.Detach_started () in
      (try
         ignore (run ~pool:p (fun () -> raise Native_defect));
         Alcotest.fail "callback defect lost"
       with Native_defect -> ());
      Pool.shutdown p;
      match try_run_result ~pool:p (fun () -> Ok 1) with
      | Ok (Not_run Shutting_down) -> ()
      | _ -> Alcotest.fail "detached pool should close")

(* nblk-2h3g: [on_settled] fires once, in the owner's context, after physical completion. *)
let settled_after_completion () =
  within (fun _env sw ->
      let p = pool ~sw () in
      let seen = ref [] in
      let on_settled = function
        | Ok v -> seen := `Value v :: !seen
        | Error _ -> seen := `Exn :: !seen
      in
      (match run ~pool:p ~on_settled (fun () -> 5) with
      | Ok 5 -> ()
      | _ -> Alcotest.fail "value");
      Alcotest.(check int) "settled once" 1 (List.length !seen);
      (try ignore (run ~pool:p ~on_settled (fun () -> raise Exit)) with Exit -> ());
      Alcotest.(check bool) "exception settles" true (List.hd !seen = `Exn);
      Pool.shutdown p)

(* nblk-2h3g: a caller that gave up is released at once; the lease is released only when
   the callback physically finishes. *)
let settled_after_cancellation () =
  within (fun env sw ->
      let p = pool ~sw () in
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
      let settled = Atomic.make 0 in
      let domain = (Domain.self () :> int) in
      let same_domain = Atomic.make true in
      let cancel = ref None in
      let caller =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  ignore
                    (run ~pool:p
                       ~on_settled:(fun _ ->
                         if (Domain.self () :> int) <> domain then
                           Atomic.set same_domain false;
                         inc settled)
                       (fun () ->
                         Eio.Semaphore.release started;
                         wait permit;
                         1));
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      Eio.Semaphore.acquire started;
      Eio.Cancel.cancel (Option.get !cancel) (Failure "caller gave up");
      Alcotest.(check bool) "caller released" true (Eio.Promise.await_exn caller);
      Alcotest.(check int) "not settled while running" 0 (Atomic.get settled);
      release permit;
      wait_until env#clock (fun () -> Atomic.get settled = 1);
      Alcotest.(check bool) "owner's domain" true (Atomic.get same_domain);
      Pool.shutdown p;
      Alcotest.(check int) "settled exactly once" 1 (Atomic.get settled))

(* nblk-2h3g: after run_result_timeout's timeout, and never for a pre-claim cancel. *)
let settled_after_timeout_not_before_claim () =
  within (fun env sw ->
      let p = pool ~sw () in
      let permit = gate () in
      let started = Eio.Semaphore.make 0 in
      let settled = ref [] in
      (match
         run_result_timeout ~pool:p ~clock:env#clock ~timeout:(Eta.Duration.ms 50)
           ~on_timeout:()
           ~on_settled:(fun o -> settled := `First o :: !settled)
           (fun () ->
             Eio.Semaphore.release started;
             wait permit;
             Ok 3)
       with
      | Error (`Timed_out ()) -> ()
      | _ -> Alcotest.fail "expected timeout");
      Eio.Semaphore.acquire started;
      let cancel = ref None in
      let queued_ran = Atomic.make false in
      let queued =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  ignore
                    (run ~pool:p
                       ~on_settled:(fun _ -> settled := `Second :: !settled)
                       (fun () -> Atomic.set queued_ran true))
                with Eio.Cancel.Cancelled _ -> ()))
      in
      wait_until env#clock (fun () -> (Pool.stats p).queued = 1 && !cancel <> None);
      Eio.Cancel.cancel (Option.get !cancel) (Failure "pre-claim");
      Eio.Promise.await_exn queued;
      Alcotest.(check int) "timed-out call not settled yet" 0 (List.length !settled);
      release permit;
      Pool.shutdown p;
      (match !settled with
      | [ `First (Ok (Ok 3)) ] -> ()
      | _ -> Alcotest.fail "expected exactly the timed-out call to settle, with its value");
      Alcotest.(check bool) "pre-claim callback never ran" false (Atomic.get queued_ran))

let () =
  Alcotest.run "eta_blocking"
    [
      ( "native",
        [
          Alcotest.test_case "nblock-a7q2 nblock-f4kx bounded typed" `Quick
            typed_and_bounded;
          Alcotest.test_case "nblock-j9wr nblock-v8ze nblock-p5dm timeout drain" `Quick
            timeout_retains_slot;
          Alcotest.test_case "nblock-v8ze queued cancellation" `Quick queued_cancellation;
          Alcotest.test_case "nblock-v8ze nblock-p5dm running cancellation" `Quick
            running_cancellation;
          Alcotest.test_case "nblock-p5dm exception detach" `Quick defects_and_detach;
          Alcotest.test_case "nblk-2h3g settled after completion" `Quick
            settled_after_completion;
          Alcotest.test_case "nblk-2h3g settled after caller cancellation" `Quick
            settled_after_cancellation;
          Alcotest.test_case "nblk-2h3g settled after timeout, never before claim" `Quick
            settled_after_timeout_not_before_claim;
        ] );
    ]
