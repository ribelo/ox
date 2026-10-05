open Ox_blocking

let concurrency value =
  match Ox.Concurrency.of_int value with
  | Ok bound -> bound
  | Error `Invalid -> Alcotest.fail "invalid test worker concurrency"

let pool ~sw ?(threads = 1) ?(queued = 1) ?(policy = Pool.Drain) () =
  Pool.create ~sw ~name:"test"
    { max_threads = concurrency threads; max_queued = queued; shutdown_policy = policy }

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
        run_result_timeout ~pool:p ~clock:env#clock ~timeout:(Ox.Duration.ms 100)
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
                  ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: The reply is incidental to this cancellation probe; the existing cancellation and physical-completion assertions decide the outcome. *)
                   let _cancelled_call_result =
                     run ~pool:p (fun () -> Atomic.set ran true)
                       [@@ox.allow
                         "ox-discarded-result: caller reply is incidental to \
                          cancellation and physical worker settlement assertions"]
                   in
                   ());
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      wait_until env#clock (fun () -> (Pool.stats p).queued = 1 && !cancel <> None);
      let cancel_context =
        match !cancel with
        | Some context -> context
        | None -> Alcotest.fail "blocking caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "test cancellation");
      Alcotest.(check bool) "queued caller released" true (Eio.Promise.await_exn second);
      Alcotest.(check int) "queue removed" 0 (Pool.stats p).queued;
      release permit;
      (* ^safe-xls8: joining the scripted first callback must also succeed. *)
      Alcotest.(check bool)
        "first callback succeeded" true
        (Result.is_ok (Eio.Promise.await_exn first));
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
                  ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: The reply is incidental to this cancellation probe; the existing cancellation and physical-completion assertions decide the outcome. *)
                   let _cancelled_call_result =
                     run ~pool:p
                       ~on_cancel:(fun () -> inc hooks)
                       (fun () ->
                         Eio.Semaphore.release started;
                         wait permit;
                         42)
                       [@@ox.allow
                         "ox-discarded-result: caller reply is incidental to \
                          cancellation and physical worker settlement assertions"]
                   in
                   ());
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      Eio.Semaphore.acquire started;
      let cancel_context =
        match !cancel with
        | Some context -> context
        | None -> Alcotest.fail "blocking caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "stop caller");
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
         ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: The callback is scripted to raise Native_defect; the existing failure sentinel rejects any normal return. *)
          let _defect_result =
            run ~pool:p (fun () -> raise Native_defect)
              [@@ox.allow
                "ox-discarded-result: scripted native exception is observed by the \
                 defect sentinel or on_settled assertion, not a normal reply"]
          in
          ());
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
      (try
         (* ^safe-xls8 ^safe-pufa ^nlint-hxar: The callback is scripted to raise Exit; the existing on_settled assertion checks exception delivery rather than a normal reply. *)
         let _defect_result =
           run ~pool:p ~on_settled (fun () -> raise Exit)
             [@@ox.allow
               "ox-discarded-result: scripted native exception is observed by the defect \
                sentinel or on_settled assertion, not a normal reply"]
         in
         ()
       with Exit -> ());
      let first_outcome =
        match !seen with
        | outcome :: _ -> outcome
        | [] -> Alcotest.fail "exception settlement was not recorded"
      in
      Alcotest.(check bool) "exception settles" true (first_outcome = `Exn);
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
                  ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: The reply is incidental to this cancellation probe; the existing cancellation and physical-completion assertions decide the outcome. *)
                   let _cancelled_call_result =
                     run ~pool:p
                       ~on_settled:(fun _ ->
                         if (Domain.self () :> int) <> domain then
                           Atomic.set same_domain false;
                         inc settled)
                       (fun () ->
                         Eio.Semaphore.release started;
                         wait permit;
                         1)
                       [@@ox.allow
                         "ox-discarded-result: caller reply is incidental to \
                          cancellation and physical worker settlement assertions"]
                   in
                   ());
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      Eio.Semaphore.acquire started;
      let cancel_context =
        match !cancel with
        | Some context -> context
        | None -> Alcotest.fail "blocking caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "caller gave up");
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
         run_result_timeout ~pool:p ~clock:env#clock ~timeout:(Ox.Duration.ms 50)
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
                  (* ^safe-xls8 ^safe-pufa ^nlint-hxar: The reply is incidental to this cancellation probe; the existing cancellation and physical-completion assertions decide the outcome. *)
                  let _cancelled_call_result =
                    run ~pool:p
                      ~on_settled:(fun _ -> settled := `Second :: !settled)
                      (fun () -> Atomic.set queued_ran true)
                      [@@ox.allow
                        "ox-discarded-result: caller reply is incidental to cancellation \
                         and physical worker settlement assertions"]
                  in
                  ()
                with Eio.Cancel.Cancelled _ -> ()))
      in
      wait_until env#clock (fun () -> (Pool.stats p).queued = 1 && !cancel <> None);
      let cancel_context =
        match !cancel with
        | Some context -> context
        | None -> Alcotest.fail "blocking caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "pre-claim");
      Eio.Promise.await_exn queued;
      Alcotest.(check int) "timed-out call not settled yet" 0 (List.length !settled);
      release permit;
      Pool.shutdown p;
      (match !settled with
      | [ `First (Ok (Ok 3)) ] -> ()
      | _ -> Alcotest.fail "expected exactly the timed-out call to settle, with its value");
      Alcotest.(check bool) "pre-claim callback never ran" false (Atomic.get queued_ran))

(* Deadlock guard for drain fixtures: every gate handed out is opened when the body ends,
   also on assertion failure or guard timeout, so the owner switch can join its workers. *)
let guarded f =
  Eio_main.run (fun env ->
      let gates = ref [] in
      let tracked_gate () =
        let g = gate () in
        gates := g :: !gates;
        g
      in
      Eio.Switch.run (fun sw ->
          Fun.protect
            ~finally:(fun () -> List.iter release !gates)
            (fun () ->
              Eio.Time.with_timeout_exn env#clock 5. (fun () -> f sw tracked_gate))))

(* Start a callback held at [permit]; return once it is physically running. *)
let start_gated ~sw ~gate p ?counter () =
  let started = Eio.Semaphore.make 0 in
  let permit = gate () in
  let call =
    Eio.Fiber.fork_promise ~sw (fun () ->
        let work () =
          Eio.Semaphore.release started;
          wait permit
        in
        match counter with
        | None -> run ~pool:p work
        | Some (settled, hook, notification_error) ->
            run ~pool:p
              ~on_settled:(fun _ ->
                inc settled;
                try Eio.Semaphore.release hook
                with Sys_error _ as ex -> notification_error := Some ex)
              work)
  in
  Eio.Semaphore.acquire started;
  (call, permit)

(* Counts hook runs; [hook] is signalled in the owner's context after each one. *)
let settled_counter () =
  let settled = Atomic.make 0 in
  let hook = Eio.Semaphore.make 0 in
  (settled, hook, ref None)

(* Notification defects are reported only after the physical callbacks have settled. *)
let check_notification (_, _, notification_error) =
  match !notification_error with None -> () | Some ex -> raise ex

(* A Drain caller in its own fiber; [Ok n] reports [seen ()] when Drain returned. *)
let drain ~sw ?(seen = fun () -> 0) p =
  Eio.Fiber.fork_promise ~sw (fun () ->
      match Pool.shutdown p with
      | () -> Ok (seen ())
      | exception ex -> Error (ex, Printexc.get_raw_backtrace ()))

let drained name promise =
  match Eio.Promise.await_exn promise with
  | Ok seen -> seen
  | Error (ex, _) -> Alcotest.failf "%s raised %s" name (Printexc.to_string ex)

let call_ok name promise =
  match Eio.Promise.await_exn promise with
  | Ok () -> ()
  | Error `Shutting_down -> Alcotest.failf "%s was not admitted" name

let pending name promise =
  Eio.Fiber.yield ();
  Alcotest.(check bool) name false (Eio.Promise.is_resolved promise)

(* nblock-5siy nblock-faq7 nblock-vm4e: two workers, two drainers. Released one at a time,
   each freed slot would go to a different historical drainer; both must join one ending
   that completes only after both callbacks and both hooks. *)
let two_drainers_join_one_ending () =
  guarded (fun sw gate ->
      let p = pool ~sw ~threads:2 () in
      let ((settled, hook, _) as counter) = settled_counter () in
      let a, permit_a = start_gated ~sw ~gate p ~counter () in
      let b, permit_b = start_gated ~sw ~gate p ~counter () in
      let seen () = Atomic.get settled in
      let d1 = drain ~sw ~seen p in
      let d2 = drain ~sw ~seen p in
      release permit_a;
      Eio.Semaphore.acquire hook;
      pending "first drainer waits for the second callback" d1;
      pending "second drainer waits for the second callback" d2;
      release permit_b;
      Alcotest.(check int) "first drainer after both hooks" 2 (drained "first" d1);
      Alcotest.(check int) "second drainer after both hooks" 2 (drained "second" d2);
      call_ok "first call" a;
      call_ok "second call" b;
      Alcotest.(check int) "each hook exactly once" 2 (Atomic.get settled);
      Alcotest.(check int) "nothing active" 0 (Pool.stats p).active;
      check_notification counter)

(* nblock-8z91 nblock-de0p nblock-vm4e: a drainer cancelled after one callback finished
   leaves an ending a surviving drainer completes; repeating it changes nothing. *)
let cancelled_drainer_leaves_drain () =
  guarded (fun sw gate ->
      let p = pool ~sw ~threads:2 () in
      let ((settled, hook, _) as counter) = settled_counter () in
      let a, permit_a = start_gated ~sw ~gate p ~counter () in
      let b, permit_b = start_gated ~sw ~gate p ~counter () in
      let cancel = ref None in
      let gave_up =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                try
                  Pool.shutdown p;
                  false
                with Eio.Cancel.Cancelled _ -> true))
      in
      release permit_a;
      Eio.Semaphore.acquire hook;
      let cancel_context =
        match !cancel with
        | Some context -> context
        | None -> Alcotest.fail "blocking caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "drainer gave up");
      Alcotest.(check bool)
        "cancelled drainer released" true
        (Eio.Promise.await_exn gave_up);
      let admitted_after_seal = Atomic.make false in
      (match try_run ~pool:p (fun () -> Atomic.set admitted_after_seal true) with
      | Not_run Shutting_down -> ()
      | _ -> Alcotest.fail "admission must stay sealed");
      let survivor = drain ~sw ~seen:(fun () -> Atomic.get settled) p in
      pending "survivor waits for the gated callback" survivor;
      release permit_b;
      Alcotest.(check int) "survivor after both hooks" 2 (drained "survivor" survivor);
      call_ok "first call" a;
      call_ok "second call" b;
      let before = Pool.stats p in
      Pool.shutdown p;
      Pool.shutdown p;
      Alcotest.(check bool) "repeated drain keeps accounting" true (before = Pool.stats p);
      Alcotest.(check int) "hooks not rerun" 2 (Atomic.get settled);
      Alcotest.(check bool) "admitted after seal" false (Atomic.get admitted_after_seal);
      check_notification counter)

(* nblock-de0p: repeated Drain of an idle pool returns at once without new accounting. *)
let repeated_drain_idle () =
  within (fun _env sw ->
      let p = pool ~sw () in
      (match run ~pool:p (fun () -> 1) with Ok 1 -> () | _ -> Alcotest.fail "value");
      Pool.shutdown p;
      let before = Pool.stats p in
      Pool.shutdown p;
      Alcotest.(check bool) "unchanged" true (before = Pool.stats p);
      Alcotest.(check int) "one completion" 1 before.completed)

(* nblock-l36w nblock-vm4e: the first Drain seals admission; queued and new work is
   rejected honestly and never starts. *)
let drain_seals_admission () =
  guarded (fun sw gate ->
      let p = pool ~sw ~threads:1 ~queued:1 () in
      let a, permit = start_gated ~sw ~gate p () in
      let queued_ran = Atomic.make false in
      let queued =
        Eio.Fiber.fork_promise ~sw (fun () ->
            run ~pool:p (fun () -> Atomic.set queued_ran true))
      in
      Alcotest.(check int) "admitted waiter" 1 (Pool.stats p).queued;
      (match try_run ~pool:p (fun () -> ()) with
      | Not_run Saturated -> ()
      | _ -> Alcotest.fail "expected saturation before drain");
      let ending = drain ~sw p in
      (match run ~pool:p (fun () -> Atomic.set queued_ran true) with
      | Error `Shutting_down -> ()
      | Ok () -> Alcotest.fail "new run admitted after seal");
      (match try_run_result ~pool:p (fun () -> Ok ()) with
      | Ok (Not_run Shutting_down) -> ()
      | _ -> Alcotest.fail "new try_run admitted after seal");
      pending "drain waits for the running callback" ending;
      release permit;
      ignore (drained "drain" ending);
      call_ok "running call" a;
      (match Eio.Promise.await_exn queued with
      | Error `Shutting_down -> ()
      | Ok () -> Alcotest.fail "queued work slipped in");
      Alcotest.(check bool) "queued callback never started" false (Atomic.get queued_ran);
      Alcotest.(check int) "only the started call completed" 1 (Pool.stats p).completed)

(* nblock-qwwp nblock-faq7: callback values, typed errors and raised defects keep their
   contract in a Drain pool; outcomes delivered to waiting callers do not fail Drain. *)
let drain_preserves_outcomes () =
  within (fun _env sw ->
      let p = pool ~sw ~threads:2 () in
      let ((settled, hook, notification_error) as counter) = settled_counter () in
      let on_settled _ =
        inc settled;
        try Eio.Semaphore.release hook
        with Sys_error _ as ex -> notification_error := Some ex
      in
      (match run_result ~pool:p ~on_settled (fun () -> Ok 3) with
      | Ok 3 -> ()
      | _ -> Alcotest.fail "value lost");
      (match run_result ~pool:p ~on_settled (fun () -> Error `Native) with
      | Error (`Callback `Native) -> ()
      | _ -> Alcotest.fail "typed callback error lost");
      (match run ~pool:p ~on_settled (fun () -> raise Native_defect) with
      | _ -> Alcotest.fail "callback defect converted"
      | exception Native_defect -> ());
      Pool.shutdown p;
      Alcotest.(check int) "each hook once before drain" 3 (Atomic.get settled);
      check_notification counter)

exception Owner_stop

(* nblock-c664: cancelling the owner switch releases the caller at once, but the owner
   joins the started native worker and its settled hook before it ends. *)
let owner_cancellation_joins_worker () =
  Eio_main.run (fun env ->
      let permit = gate () in
      let caller_released, set_caller_released = Eio.Promise.create () in
      let notification_error = ref None in
      let settled = Atomic.make 0 in
      let owner_done = Atomic.make false in
      let settled_at_owner_end = ref (-1) in
      Eio.Time.with_timeout_exn env#clock 5. (fun () ->
          Eio.Fiber.both
            (fun () ->
              (match
                 Eio.Switch.run (fun sw ->
                     let p = pool ~sw () in
                     let started = Eio.Semaphore.make 0 in
                     Eio.Fiber.fork ~sw (fun () ->
                         (* ^safe-xls8 ^safe-pufa ^nlint-hxar: The reply is incidental to this cancellation probe; the existing cancellation and physical-completion assertions decide the outcome. *)
                         let _cancelled_call_result =
                           run ~pool:p
                             ~on_cancel:(fun () ->
                               try Eio.Promise.resolve set_caller_released ()
                               with Invalid_argument _ as ex ->
                                 notification_error := Some ex)
                             ~on_settled:(fun _ -> inc settled)
                             (fun () ->
                               Eio.Semaphore.release started;
                               wait permit)
                             [@@ox.allow
                               "ox-discarded-result: caller reply is incidental to \
                                cancellation and physical worker settlement assertions"]
                         in
                         ());
                     Eio.Semaphore.acquire started;
                     Eio.Switch.fail sw Owner_stop)
               with
              | () -> Alcotest.fail "owner switch should fail"
              | exception Owner_stop -> ());
              settled_at_owner_end := Atomic.get settled;
              Atomic.set owner_done true)
            (fun () ->
              Fun.protect
                ~finally:(fun () -> release permit)
                (fun () ->
                  Eio.Promise.await caller_released;
                  for _ = 1 to 10 do
                    Eio.Fiber.yield ()
                  done;
                  Alcotest.(check bool)
                    "owner still joining the worker" false (Atomic.get owner_done);
                  Alcotest.(check int) "not settled while running" 0 (Atomic.get settled))));
      Alcotest.(check int) "hook ran before the owner ended" 1 !settled_at_owner_end;
      match !notification_error with None -> () | Some ex -> raise ex)

let () =
  Alcotest.run "ox_blocking"
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
      ( "drain",
        [
          Alcotest.test_case "nblock-5siy nblock-faq7 nblock-vm4e two drainers" `Quick
            two_drainers_join_one_ending;
          Alcotest.test_case "nblock-8z91 nblock-de0p nblock-vm4e cancelled drainer"
            `Quick cancelled_drainer_leaves_drain;
          Alcotest.test_case "nblock-de0p repeated idle drain" `Quick repeated_drain_idle;
          Alcotest.test_case "nblock-l36w nblock-vm4e drain seals admission" `Quick
            drain_seals_admission;
          Alcotest.test_case "nblock-qwwp nblock-faq7 drain preserves outcomes" `Quick
            drain_preserves_outcomes;
          Alcotest.test_case "nblock-c664 owner cancellation joins worker" `Quick
            owner_cancellation_joins_worker;
        ] );
    ]
