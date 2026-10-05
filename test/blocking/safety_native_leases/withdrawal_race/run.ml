(* ^safe-sw86 ^safe-bt9f: public lease/shutdown observations on verbatim producer source.
   The private scheduler import only gates a genuinely submitted systhread before claim.
   No production test hook, scheduler replacement, or installed-consumer fallback. *)
open Preclaim_producer.Ox_blocking

let concurrency value =
  match Ox.Concurrency.of_int value with
  | Ok bound -> bound
  | Error `Invalid -> Alcotest.fail "invalid test worker concurrency"

exception Release_defect

let[@inline never] release_marker () = raise Release_defect

let observe f =
  match f () with () -> Ok () | exception ex -> Error (ex, Printexc.get_raw_backtrace ())

let check_defect original = function
  | Error (Release_defect, bt) ->
      let original = Printexc.raw_backtrace_to_string (Option.get !original) in
      Alcotest.(check bool) "nonempty original trace" true (original <> "");
      Alcotest.(check bool)
        "original release trace retained" true
        (String.starts_with ~prefix:original (Printexc.raw_backtrace_to_string bt))
  | _ -> Alcotest.fail "Drain missed retained Unclaimed release defect"

let withdrawn_release () =
  Printexc.record_backtrace true;
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          Eio.Time.with_timeout_exn env#clock 5. (fun () ->
              let p =
                Pool.create ~sw
                  { max_threads = concurrency 1; max_queued = 1; shutdown_policy = Drain }
              in
              let native = Native_claim_gate.arm () in
              let entered, enter = Eio.Promise.create () in
              let release_ready, release_continue = Eio.Promise.create () in
              let context = ref None in
              let releases = ref 0 in
              let ran = Atomic.make 0 in
              let original = ref None in
              Fun.protect
                ~finally:(fun () ->
                  Native_claim_gate.unblock native;
                  ignore (Eio.Promise.try_resolve release_continue ()))
                (fun () ->
                  let caller =
                    Eio.Fiber.fork_promise ~sw (fun () ->
                        Eio.Cancel.sub (fun ctx ->
                            context := Some ctx;
                            match
                              run_leased_result ~pool:p
                                ~release:(function
                                  | Settled _ ->
                                      Alcotest.fail "withdrawn callback settled"
                                  | Unclaimed -> (
                                      incr releases;
                                      Eio.Promise.resolve enter ();
                                      Eio.Promise.await release_ready;
                                      match release_marker () with
                                      | () -> assert false
                                      | exception ex ->
                                          let bt = Printexc.get_raw_backtrace () in
                                          original := Some bt;
                                          Printexc.raise_with_backtrace ex bt))
                                (fun () ->
                                  ignore (Atomic.fetch_and_add ran 1);
                                  Ok ())
                            with
                            | _ -> false
                            | exception Eio.Cancel.Cancelled _ -> true))
                  in
                  Native_claim_gate.await_submitted native;
                  Eio.Cancel.cancel (Option.get !context) Exit;
                  Eio.Promise.await entered;
                  Native_claim_gate.unblock native;
                  (* The driver's owner-side finalizer and production state-2 handler
                     cannot suspend between this notification and the handler's return. *)
                  Native_claim_gate.await_returned native;
                  (match try_run ~pool:p (fun () -> 23) with
                  | Not_run Saturated -> ()
                  | _ ->
                      Alcotest.fail
                        "withdrawn worker released caller-owned capacity early");
                  let drain =
                    Eio.Fiber.fork_promise ~sw (fun () ->
                        observe (fun () -> Pool.shutdown p))
                  in
                  Eio.Fiber.yield ();
                  Alcotest.(check bool)
                    "Drain waits for Unclaimed cleanup" false
                    (Eio.Promise.is_resolved drain);
                  Eio.Promise.resolve release_continue ();
                  Alcotest.(check bool)
                    "caller cancellation preserved" true
                    (Eio.Promise.await_exn caller);
                  check_defect original (Eio.Promise.await_exn drain);
                  check_defect original (observe (fun () -> Pool.shutdown p));
                  Alcotest.(check int) "Unclaimed delivered exactly once" 1 !releases;
                  Alcotest.(check int) "withdrawn callback never ran" 0 (Atomic.get ran)))))

let () =
  Alcotest.run "submitted native withdrawal"
    [
      ( "safe-sw86 safe-bt9f",
        [
          Alcotest.test_case "suspended Unclaimed owns admitted slot" `Quick
            withdrawn_release;
        ] );
    ]
