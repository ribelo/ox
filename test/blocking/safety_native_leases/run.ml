(* ^safe-zgfv ^safe-sw86 ^safe-bt9f ^safe-fr73: public blocking seam only.
   Native barriers retain real Unix descriptors and buffers, not a simulated lease.
   This is a runtime witness, not production NemaOwner adoption (^safe-m6vf). *)
open Ox_blocking

let pool ~sw ?(policy = Pool.Drain) () =
  Pool.create ~sw { max_threads = 1; max_queued = 1; shutdown_policy = policy }

let guarded f =
  Eio_main.run (fun env ->
      let gates = ref [] in
      let gate () =
        let g = Semaphore.Counting.make 0 in
        gates := g :: !gates;
        g
      in
      Eio.Switch.run (fun sw ->
          Fun.protect
            ~finally:(fun () -> List.iter Semaphore.Counting.release !gates)
            (fun () -> Eio.Time.with_timeout_exn env#clock 5. (fun () -> f env sw gate))))

let inc n = ignore (Atomic.fetch_and_add n 1)
let check_count name n count = Alcotest.(check int) name n (Atomic.get count)
let check_ok name = function Ok _ -> () | Error _ -> Alcotest.fail name

let cancellation f =
  match f () with _ -> false | exception Eio.Cancel.Cancelled _ -> true

let pending name promise =
  Eio.Fiber.yield ();
  Alcotest.(check bool) name false (Eio.Promise.is_resolved promise)

let new_admission p =
  match run_leased_result ~pool:p ~release:(fun _ -> ()) (fun () -> Ok 19) with
  | Ok 19 -> ()
  | _ -> Alcotest.fail "capacity-one pool did not admit replacement before Drain"

exception Native_defect
exception Release_defect
exception Owner_stop

let[@inline never] raise_marker ex = raise ex

let backtrace ex =
  match raise_marker ex with
  | () -> assert false
  | exception (Eio.Cancel.Cancelled _ as ex) -> raise ex
  | exception _ -> Printexc.get_raw_backtrace ()

let check_trace original observed =
  let original = Printexc.raw_backtrace_to_string original in
  Alcotest.(check bool) "nonempty original trace" true (original <> "");
  Alcotest.(check bool)
    "original trace retained" true
    (String.starts_with ~prefix:original (Printexc.raw_backtrace_to_string observed))

(* ^safe-sw86: terminal once for success, typed failure and native exception. *)
let outcomes () =
  Printexc.record_backtrace true;
  guarded (fun _ sw _ ->
      let p = pool ~sw () in
      let seen = ref [] in
      let release ending = seen := ending :: !seen in
      check_ok "success" (run_leased_result ~pool:p ~release (fun () -> Ok 7));
      (match run_leased_result ~pool:p ~release (fun () -> Error `Native) with
      | Error (`Callback `Native) -> ()
      | _ -> Alcotest.fail "callback error lost");
      let bt = backtrace Native_defect in
      (match
         run_leased_result ~pool:p ~release (fun () ->
             Printexc.raise_with_backtrace Native_defect bt)
       with
      | _ -> Alcotest.fail "native defect converted"
      | exception Native_defect -> check_trace bt (Printexc.get_raw_backtrace ()));
      (match List.rev !seen with
      | [
       Settled (Ok (Ok 7)); Settled (Ok (Error `Native)); Settled (Error Native_defect);
      ] ->
          ()
      | _ -> Alcotest.fail "terminal outcomes or exact-once wrong");
      new_admission p;
      Pool.shutdown p)

(* ^safe-sw86 ^safe-bt9f: rejection cannot leave a future callback. *)
let rejection () =
  guarded (fun _ sw _ ->
      let ran = Atomic.make 0 in
      let ends = Atomic.make 0 in
      let release = function
        | Unclaimed -> inc ends
        | Settled _ -> Alcotest.fail "rejected job settled"
      in
      let fn () =
        inc ran;
        Ok ()
      in
      let detached = pool ~sw ~policy:Pool.Detach_started () in
      (match run_leased_result ~pool:detached ~release fn with
      | Error `Requires_drain -> ()
      | _ -> Alcotest.fail "Detach admitted leased job");
      let closed = pool ~sw () in
      Pool.shutdown closed;
      (match run_leased_result ~pool:closed ~release fn with
      | Error `Shutting_down -> ()
      | _ -> Alcotest.fail "closed pool admitted job");
      Eio.Fiber.yield ();
      check_count "two Unclaimed" 2 ends;
      check_count "neither callback executed" 0 ran;
      Pool.shutdown detached)

(* ^safe-sw86: cancelled admission has no slot to release. A replacement admission
   before shutdown catches mistakenly releasing the occupied native slot. *)
let before_claim ~defective () =
  Printexc.record_backtrace true;
  guarded (fun _ sw gate ->
      let p = pool ~sw () in
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
      let first =
        Eio.Fiber.fork_promise ~sw (fun () ->
            run_leased_result ~pool:p
              ~release:(fun _ -> ())
              (fun () ->
                Eio.Semaphore.release started;
                Semaphore.Counting.acquire permit;
                Ok ()))
      in
      Eio.Semaphore.acquire started;
      let ends = Atomic.make 0 in
      let ran = Atomic.make 0 in
      let cancel = ref None in
      let bt = backtrace Release_defect in
      let queued =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                cancellation (fun () ->
                    run_leased_result ~pool:p
                      ~release:(function
                        | Unclaimed ->
                            inc ends;
                            if defective then
                              Printexc.raise_with_backtrace Release_defect bt
                        | Settled _ -> Alcotest.fail "preclaim settled")
                      (fun () ->
                        inc ran;
                        Ok ()))))
      in
      Alcotest.(check int) "admission barrier" 1 (Pool.stats p).queued;
      Eio.Cancel.cancel (Option.get !cancel) (Failure "before claim");
      Alcotest.(check bool)
        "original Eio cancellation preserved" true
        (Eio.Promise.await_exn queued);
      check_count "Unclaimed once before physical return" 1 ends;
      check_count "not executed" 0 ran;
      Alcotest.(check int) "first worker still active" 1 (Pool.stats p).active;
      Semaphore.Counting.release permit;
      check_ok "first worker" (Eio.Promise.await_exn first);
      new_admission p;
      if defective then
        for _ = 1 to 2 do
          match Pool.shutdown p with
          | () -> Alcotest.fail "Unclaimed defect swallowed"
          | exception Release_defect -> check_trace bt (Printexc.get_raw_backtrace ())
        done
      else Pool.shutdown p;
      check_count "cannot execute later" 0 ran;
      check_count "no duplicate terminal" 1 ends)

(* ^safe-sw86: synchronous fork rejection releases both lease and acquired pool slot. *)
let startup_failure () =
  guarded (fun _ _sw _ ->
      let p = Eio.Switch.run (fun sw -> pool ~sw ()) in
      let ends = Atomic.make 0 in
      let ran = Atomic.make 0 in
      (match
         run_leased_result ~pool:p
           ~release:(function
             | Unclaimed -> inc ends | Settled _ -> Alcotest.fail "startup settled")
           (fun () ->
             inc ran;
             Ok ())
       with
      | _ -> Alcotest.fail "finished owner accepted job"
      | exception Invalid_argument _ -> ());
      Pool.shutdown p;
      check_count "startup Unclaimed once" 1 ends;
      check_count "startup callback impossible" 0 ran)

(* ^safe-zgfv ^safe-sw86 ^safe-bt9f: actual pipe descriptor and byte buffer live past
   caller cancellation/timeout. The systhread is held before its native read; only
   physical return authorizes owner-context close. A late observer defect must still
   close finally, return capacity one BEFORE shutdown, and retain only exn+trace. *)
let native_lifetime ~timeout ~defective () =
  Printexc.record_backtrace true;
  guarded (fun env sw gate ->
      let p = pool ~sw () in
      let fd, writer = Unix.pipe ~cloexec:true () in
      let buffer = Bytes.create 1 in
      let closed = Atomic.make 0 in
      let done_native = Atomic.make false in
      let interrupted = Atomic.make 0 in
      let native_thread = Atomic.make None in
      let owner_domain = Domain.self () in
      let owner_thread = Thread.id (Thread.self ()) in
      let started = Eio.Semaphore.make 0 in
      let settled = Eio.Semaphore.make 0 in
      let permit = gate () in
      let bt = backtrace Release_defect in
      Fun.protect
        ~finally:(fun () ->
          Unix.close writer;
          if Atomic.get closed = 0 then Unix.close fd)
        (fun () ->
          let release = function
            | Unclaimed -> Alcotest.fail "claimed descriptor was withdrawn"
            | Settled outcome ->
                Fun.protect
                  ~finally:(fun () ->
                    Unix.close fd;
                    inc closed;
                    Eio.Semaphore.release settled)
                  (fun () ->
                    Alcotest.(check bool)
                      "physical done before close" true (Atomic.get done_native);
                    Alcotest.(check bool)
                      "owner domain" true
                      (Domain.self () = owner_domain);
                    Alcotest.(check int)
                      "owner Eio thread" owner_thread
                      (Thread.id (Thread.self ()));
                    Alcotest.(check bool)
                      "not native thread" true
                      (Atomic.get native_thread <> Some (Thread.id (Thread.self ())));
                    Eio.Fiber.yield ();
                    check_ok "physical result" outcome;
                    if defective then Printexc.raise_with_backtrace Release_defect bt)
          in
          let native () =
            Atomic.set native_thread (Some (Thread.id (Thread.self ())));
            Eio.Semaphore.release started;
            Semaphore.Counting.acquire permit;
            let count = Unix.read fd buffer 0 1 in
            Atomic.set done_native true;
            Ok count
          in
          let cancel = ref None in
          let caller =
            Eio.Fiber.fork_promise ~sw (fun () ->
                Eio.Cancel.sub (fun ctx ->
                    cancel := Some ctx;
                    let call () =
                      run_leased_result ~pool:p ~release
                        ~on_cancel:(fun () -> inc interrupted)
                        native
                    in
                    if timeout then
                      match
                        Eio.Time.with_timeout env#clock 0.01 (fun () ->
                            Result.map_error
                              (fun e ->
                                (e
                                  :> [ `Timeout
                                     | `Callback of _
                                     | `Requires_drain
                                     | `Shutting_down ]))
                              (call ()))
                      with
                      | Error `Timeout -> true
                      | _ -> false
                    else cancellation call))
          in
          Eio.Semaphore.acquire started;
          if not timeout then
            Eio.Cancel.cancel (Option.get !cancel) (Failure "after actual claim");
          Alcotest.(check bool)
            "caller stops before physical completion" true
            (Eio.Promise.await_exn caller);
          check_count "interruption once" 1 interrupted;
          check_count "descriptor still owned" 0 closed;
          (match try_run ~pool:p (fun () -> ()) with
          | Not_run Saturated -> ()
          | _ -> Alcotest.fail "slot released early");
          (* Real native descriptor is usable while the waiter has gone. *)
          Alcotest.(check int)
            "native write count" 1
            (Unix.write writer (Bytes.of_string "x") 0 1);
          Semaphore.Counting.release permit;
          Eio.Semaphore.acquire settled;
          new_admission p;
          check_count "native close completed before ANY Drain" 1 closed;
          Alcotest.(check char) "retained native buffer" 'x' (Bytes.get buffer 0);
          if defective then
            for _ = 1 to 2 do
              match Pool.shutdown p with
              | () -> Alcotest.fail "late cleanup defect swallowed"
              | exception Release_defect -> check_trace bt (Printexc.get_raw_backtrace ())
            done
          else Pool.shutdown p;
          check_count "terminal close exactly once" 1 closed))

(* ^safe-bt9f: live release defects return capacity before Drain; no retained failure. *)
let live_release_defect () =
  Printexc.record_backtrace true;
  guarded (fun _ sw _ ->
      let p = pool ~sw () in
      let ends = Atomic.make 0 in
      let bt = backtrace Release_defect in
      (match
         run_leased_result ~pool:p
           ~release:(fun _ ->
             inc ends;
             Printexc.raise_with_backtrace Release_defect bt)
           (fun () -> Ok ())
       with
      | _ -> Alcotest.fail "live defect lost"
      | exception Release_defect -> check_trace bt (Printexc.get_raw_backtrace ()));
      new_admission p;
      Pool.shutdown p;
      Pool.shutdown p;
      check_count "live release once" 1 ends)

(* ^safe-bt9f: Drain waits for the terminal release itself, not only native return. *)
let drain_waits_release () =
  guarded (fun _ sw gate ->
      let p = pool ~sw () in
      let physical = gate () in
      let started = Eio.Semaphore.make 0 in
      let release_entered = Eio.Semaphore.make 0 in
      let release_permit = Eio.Semaphore.make 0 in
      let ends = Atomic.make 0 in
      let caller =
        Eio.Fiber.fork_promise ~sw (fun () ->
            run_leased_result ~pool:p
              ~release:(fun _ ->
                Eio.Semaphore.release release_entered;
                Eio.Semaphore.acquire release_permit;
                inc ends)
              (fun () ->
                Eio.Semaphore.release started;
                Semaphore.Counting.acquire physical;
                Ok ()))
      in
      Eio.Semaphore.acquire started;
      let drained = Eio.Fiber.fork_promise ~sw (fun () -> Pool.shutdown p) in
      pending "Drain blocked by native work" drained;
      Semaphore.Counting.release physical;
      Eio.Semaphore.acquire release_entered;
      pending "Drain blocked by terminal release" drained;
      pending "live caller blocked by terminal release" caller;
      Eio.Semaphore.release release_permit;
      Eio.Promise.await_exn drained;
      check_ok "live caller" (Eio.Promise.await_exn caller);
      check_count "release before Drain" 1 ends)

(* ^safe-sw86: free-slot submission races actual claim with cancellation. Whichever
   wins must agree with the terminal outcome; Unclaimed can never execute later. *)
let claim_withdraw_race () =
  guarded (fun _ sw _ ->
      let p = pool ~sw () in
      for _ = 1 to 100 do
        let ran = Atomic.make 0 in
        let ends = ref [] in
        let cancel = ref None in
        let caller =
          Eio.Fiber.fork_promise ~sw (fun () ->
              Eio.Cancel.sub (fun ctx ->
                  cancel := Some ctx;
                  cancellation (fun () ->
                      run_leased_result ~pool:p
                        ~release:(fun ending -> ends := ending :: !ends)
                        (fun () ->
                          inc ran;
                          Ok ()))))
        in
        Eio.Cancel.cancel (Option.get !cancel) (Failure "claim/withdraw race");
        let _cancelled = Eio.Promise.await_exn caller in
        new_admission p;
        match !ends with
        | [ Unclaimed ] -> check_count "withdraw excludes later execution" 0 ran
        | [ Settled (Ok (Ok ())) ] -> check_count "claimed job physically completed" 1 ran
        | _ -> Alcotest.fail "race terminal not exactly once"
      done;
      Pool.shutdown p)

(* ^safe-bt9f: cancellation after the worker publishes a hook failure hands the
   failure to the cancellation handler, which must release capacity before Drain. *)
let published_failure_cancel () =
  Printexc.record_backtrace true;
  guarded (fun _ sw _ ->
      let p = pool ~sw () in
      let cancel = ref None in
      let ends = Atomic.make 0 in
      let bt = backtrace Release_defect in
      let caller =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                cancellation (fun () ->
                    run_leased_result ~pool:p
                      ~release:(fun _ ->
                        inc ends;
                        Eio.Cancel.cancel (Option.get !cancel)
                          (Failure "published release defect");
                        Printexc.raise_with_backtrace Release_defect bt)
                      (fun () -> Ok ()))))
      in
      Alcotest.(check bool)
        "original pending cancellation" true
        (Eio.Promise.await_exn caller);
      new_admission p;
      for _ = 1 to 2 do
        match Pool.shutdown p with
        | () -> Alcotest.fail "published release defect swallowed"
        | exception Release_defect -> check_trace bt (Printexc.get_raw_backtrace ())
      done;
      check_count "published release once" 1 ends)

(* ^safe-zgfv ^safe-bt9f: native defects after cancellation are still delivered to
   the owner release with the original physical outcome. *)
let late_native_defect () =
  guarded (fun _ sw gate ->
      let p = pool ~sw () in
      let started = Eio.Semaphore.make 0 in
      let settled = Eio.Semaphore.make 0 in
      let permit = gate () in
      let ends = Atomic.make 0 in
      let cancel = ref None in
      let caller =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun ctx ->
                cancel := Some ctx;
                cancellation (fun () ->
                    run_leased_result ~pool:p
                      ~release:(function
                        | Settled (Error Native_defect) ->
                            inc ends;
                            Eio.Semaphore.release settled
                        | _ -> Alcotest.fail "late native defect lost")
                      (fun () ->
                        Eio.Semaphore.release started;
                        Semaphore.Counting.acquire permit;
                        raise Native_defect))))
      in
      Eio.Semaphore.acquire started;
      Eio.Cancel.cancel (Option.get !cancel) (Failure "late native failure");
      Alcotest.(check bool) "caller cancelled" true (Eio.Promise.await_exn caller);
      check_count "release not premature" 0 ends;
      Semaphore.Counting.release permit;
      Eio.Semaphore.acquire settled;
      new_admission p;
      Pool.shutdown p;
      check_count "late native defect terminal once" 1 ends)

(* ^safe-bt9f: cancellation of the owning switch still joins physical work and
   protected terminal release, even when release itself uses an Eio operation. *)
let owner_cancellation () =
  guarded (fun _ sw gate ->
      let started = Eio.Semaphore.make 0 in
      let owner_failed = Eio.Semaphore.make 0 in
      let owner_done = Atomic.make false in
      let native_done = Atomic.make false in
      let ends = Atomic.make 0 in
      let permit = gate () in
      let owner =
        Eio.Fiber.fork_promise ~sw (fun () ->
            match
              Eio.Switch.run (fun owner_sw ->
                  let p = pool ~sw:owner_sw () in
                  Eio.Fiber.fork ~sw:owner_sw (fun () ->
                      let _cancelled =
                        cancellation (fun () ->
                            run_leased_result ~pool:p
                              ~release:(function
                                | Settled _ ->
                                    Eio.Fiber.yield ();
                                    Alcotest.(check bool)
                                      "native done before protected terminal" true
                                      (Atomic.get native_done);
                                    inc ends
                                | Unclaimed -> Alcotest.fail "owner cancelled after claim")
                              (fun () ->
                                Eio.Semaphore.release started;
                                Semaphore.Counting.acquire permit;
                                Atomic.set native_done true;
                                Ok ()))
                      in
                      ());
                  Eio.Semaphore.acquire started;
                  Eio.Semaphore.release owner_failed;
                  raise Owner_stop)
            with
            | _ -> Alcotest.fail "owner failure disappeared"
            | exception Owner_stop -> Atomic.set owner_done true)
      in
      Eio.Semaphore.acquire owner_failed;
      pending "owner joins native work" owner;
      check_count "no early terminal during owner cancellation" 0 ends;
      Alcotest.(check bool) "owner not closed" false (Atomic.get owner_done);
      Semaphore.Counting.release permit;
      Eio.Promise.await_exn owner;
      check_count "protected release despite owner cancellation" 1 ends)

let () =
  Alcotest.run "native leases"
    [
      ( "lease",
        [
          Alcotest.test_case "safe-sw86 outcomes" `Quick outcomes;
          Alcotest.test_case "safe-sw86 safe-bt9f rejection" `Quick rejection;
          Alcotest.test_case "safe-sw86 before claim" `Quick
            (before_claim ~defective:false);
          Alcotest.test_case "safe-sw86 Unclaimed defect preserves cancellation" `Quick
            (before_claim ~defective:true);
          Alcotest.test_case "safe-sw86 owner startup failure" `Quick startup_failure;
          Alcotest.test_case "safe-zgfv cancellation native lifetime" `Quick
            (native_lifetime ~timeout:false ~defective:false);
          Alcotest.test_case "safe-zgfv timeout native lifetime" `Quick
            (native_lifetime ~timeout:true ~defective:false);
          Alcotest.test_case "safe-zgfv safe-bt9f late defect capacity one before Drain"
            `Quick
            (native_lifetime ~timeout:false ~defective:true);
          Alcotest.test_case "safe-bt9f live defect capacity one before Drain" `Quick
            live_release_defect;
          Alcotest.test_case "safe-bt9f Drain waits terminal" `Quick drain_waits_release;
          Alcotest.test_case "safe-sw86 actual claim withdraw race" `Quick
            claim_withdraw_race;
          Alcotest.test_case "safe-bt9f published failure cancellation handoff" `Quick
            published_failure_cancel;
          Alcotest.test_case "safe-zgfv late native defect" `Quick late_native_defect;
          Alcotest.test_case "safe-bt9f owner cancellation joins protected terminal"
            `Quick owner_cancellation;
        ] );
    ]
