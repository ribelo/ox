(* ^safe-vske ^safe-0ozq ^safe-fr73: intentional no-raise violations are
   negative source-gate evidence; these public-library runtime regressions still
   assert defensive settlement, lifetime and Detach behaviour. *)
open Ox_blocking

let concurrency value =
  match Ox.Concurrency.of_int value with
  | Ok bound -> bound
  | Error `Invalid -> Alcotest.fail "invalid test worker concurrency"

let pool ~sw ?(threads = 1) ?(queued = 1) ?(policy = Pool.Drain) () =
  Pool.create ~sw ~name:"test"
    { max_threads = concurrency threads; max_queued = queued; shutdown_policy = policy }

let gate () = Semaphore.Counting.make 0
let release = Semaphore.Counting.release
let wait = Semaphore.Counting.acquire

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

let drain ~sw ?(seen = fun () -> 0) p =
  Eio.Fiber.fork_promise ~sw (fun () ->
      match Pool.shutdown p with
      | () -> Ok (seen ())
      | exception ex -> Error (ex, Printexc.get_raw_backtrace ()))

let pending name promise =
  Eio.Fiber.yield ();
  Alcotest.(check bool) name false (Eio.Promise.is_resolved promise)

exception Hook_live
exception Hook_abandoned

let[@inline never] raise_marker ex = raise ex

let backtrace_of ex =
  (* ^nlintc-du4v: marker backtraces are test data, never a cancellation boundary. *)
  match raise_marker ex with
  | () -> assert false
  | exception (Eio.Cancel.Cancelled _ as cancelled) -> raise cancelled
  | exception _ -> Printexc.get_raw_backtrace ()

let bt_string = Printexc.raw_backtrace_to_string

(* A re-raise appends the frames it crosses; the original frames must come first. *)
let keeps_backtrace name ~original observed =
  Alcotest.(check bool)
    name true
    (String.starts_with ~prefix:(bt_string original) (bt_string observed))

(* nblock-l78q nblock-vm4e: a hook defect after caller cancellation is retained and raised,
   with its original backtrace, by concurrent and repeated Drains; a still-waiting caller
   observes its own hook defect, which is not retained. *)
let retained_hook_defect () =
  Printexc.record_backtrace true;
  guarded (fun sw gate ->
      let p = pool ~sw ~threads:2 () in
      let live_bt = backtrace_of Hook_live in
      (match
         run ~pool:p
           ~on_settled:(fun _ -> Printexc.raise_with_backtrace Hook_live live_bt)
           (fun () -> 1)
       with
      | _ -> Alcotest.fail "waiting caller lost its hook defect"
      | exception Hook_live ->
          keeps_backtrace "waiting caller sees original backtrace" ~original:live_bt
            (Printexc.get_raw_backtrace ()));
      let abandoned_bt = backtrace_of Hook_abandoned in
      Alcotest.(check bool) "fixture has a backtrace" true (bt_string abandoned_bt <> "");
      let started = Eio.Semaphore.make 0 in
      let permit = gate () in
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
                         Printexc.raise_with_backtrace Hook_abandoned abandoned_bt)
                       (fun () ->
                         Eio.Semaphore.release started;
                         wait permit)
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
        | None ->
            Alcotest.fail "unsafe callback caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "caller gave up");
      Alcotest.(check bool) "caller released" true (Eio.Promise.await_exn caller);
      let d1 = drain ~sw p in
      let d2 = drain ~sw p in
      pending "drain waits for the abandoned callback" d1;
      release permit;
      let expect_retained name = function
        | Ok _ -> Alcotest.failf "%s reported a successful drain" name
        | Error (Hook_abandoned, bt) ->
            keeps_backtrace
              (name ^ " keeps the original backtrace")
              ~original:abandoned_bt bt
        | Error (ex, _) -> Alcotest.failf "%s raised %s" name (Printexc.to_string ex)
      in
      expect_retained "first drain" (Eio.Promise.await_exn d1);
      expect_retained "second drain" (Eio.Promise.await_exn d2);
      expect_retained "repeated drain" (Eio.Promise.await_exn (drain ~sw p));
      Alcotest.(check int) "physically completed" 2 (Pool.stats p).completed)

(* nblock-l78q: Detach_started keeps physical completion and hook execution after caller
   cancellation, without reporting the abandoned hook defect. *)
let detach_keeps_policy () =
  guarded (fun sw gate ->
      let p = pool ~sw ~policy:Pool.Detach_started () in
      let started = Eio.Semaphore.make 0 in
      let hook = Eio.Semaphore.make 0 in
      let permit = gate () in
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
                         Eio.Semaphore.release hook;
                         raise Hook_abandoned)
                       (fun () ->
                         Eio.Semaphore.release started;
                         wait permit)
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
        | None ->
            Alcotest.fail "unsafe callback caller cancellation context was not captured"
      in
      Eio.Cancel.cancel cancel_context (Failure "caller gave up");
      Alcotest.(check bool) "caller released" true (Eio.Promise.await_exn caller);
      Pool.shutdown p;
      Alcotest.(check int) "started call detached" 1 (Pool.stats p).detached;
      release permit;
      Eio.Semaphore.acquire hook;
      Alcotest.(check int) "physically completed" 1 (Pool.stats p).completed;
      Pool.shutdown p)

let () =
  Alcotest.run "ox_blocking unsafe callbacks"
    [
      ( "drain",
        [
          Alcotest.test_case
            "nblock-l78q nblock-vm4e safe-vske safe-0ozq retained hook defect" `Quick
            retained_hook_defect;
          Alcotest.test_case "nblock-l78q safe-vske safe-0ozq detach keeps policy" `Quick
            detach_keeps_policy;
        ] );
    ]
