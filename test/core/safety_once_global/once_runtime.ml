(* ^nonce-ldtz ^nonce-r7mi ^nonce-4jzx ^nonce-nngp ^nonce-lrzq ^nonce-mjpe. *)
open Ox

exception Boom

let check_int = Alcotest.(check int)
let check_bool = Alcotest.(check bool)

let reused f =
  match f () with
  | _ -> Alcotest.fail "second invocation must be Invalid_argument"
  | exception Invalid_argument _ -> ()

let guard_result () =
  let calls = ref 0 in
  let f =
    Once.guard (fun () ->
        incr calls;
        42)
  in
  check_int "first result" 42 (f ());
  reused f;
  check_int "entered once" 1 !calls;
  let dropped = ref 0 in
  let _never_called = Once.guard (fun () -> incr dropped) in
  check_int "affine does not mean must-run" 0 !dropped

let guard_defect () =
  let calls = ref 0 in
  let f =
    Once.guard (fun () ->
        incr calls;
        raise Boom)
  in
  (match f () with _ -> Alcotest.fail "defect must propagate" | exception Boom -> ());
  reused f;
  check_int "defect never reopens guard" 1 !calls

let guard_reentrant () =
  let callback = ref (fun () -> ()) in
  let f = Once.guard (fun () -> reused !callback) in
  callback := f;
  f ();
  reused f

let guard_domains () =
  let calls = Atomic.make 0 in
  let f = Once.guard (fun () -> ignore (Atomic.fetch_and_add calls 1)) in
  let domains =
    List.init 16 (fun _ ->
        Domain.spawn (fun () ->
            match f () with () -> 1 | exception Invalid_argument _ -> 0))
  in
  check_int "one winning invocation" 1
    (List.fold_left (fun n d -> n + Domain.join d) 0 domains);
  check_int "one callback entry across domains" 1 (Atomic.get calls)

let guard_cancel () =
  Eio_mock.Backend.run (fun () ->
      let ready, resolve = Eio.Promise.create () in
      let entered = ref 0 and cleaned = ref 0 in
      let f =
        Once.guard (fun () ->
            incr entered;
            Eio.Promise.resolve resolve ();
            Fun.protect Eio.Fiber.await_cancel ~finally:(fun () -> incr cleaned))
      in
      Eio.Fiber.first f (fun () -> Eio.Promise.await ready);
      check_int "cancelled callback awaited" 1 !cleaned;
      reused f;
      check_int "cancellation never reopens guard" 1 !entered)

let releases () =
  Eio_mock.Backend.run (fun () ->
      let releases = ref [] and finished = ref None in
      let result =
        Eio.Switch.run (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                finished := Some scope;
                Scope.on_release scope (fun () ->
                    Eio.Fiber.check ();
                    releases := 1 :: !releases);
                let resource =
                  Resource.use_in_scope ~sw:(Scope.switch scope)
                    (fun () -> 2)
                    (fun n ->
                      Eio.Fiber.check ();
                      releases := n :: !releases)
                in
                check_int "acquire result" 2 resource;
                Error "typed"))
      in
      check_bool "typed error preserved" true (result = Error "typed");
      Alcotest.(check (list int)) "reverse registration, no duplicates" [ 1; 2 ] !releases;
      let immediate = ref 0 in
      (match
         Scope.on_release (Option.get !finished) (fun () ->
             Eio.Fiber.check ();
             incr immediate)
       with
      | () -> Alcotest.fail "finished switch must reject registration"
      | exception Invalid_argument _ -> ());
      check_int "finished switch releases before rejecting" 1 !immediate;
      let defects = ref 0 in
      (match
         Scope.on_release (Option.get !finished) (fun () ->
             incr defects;
             raise Boom)
       with
      | () -> Alcotest.fail "finished release defect must propagate"
      | exception ex ->
          check_bool "Eio wraps immediate release defect" true
            (String.ends_with ~suffix:"Switch.Release_error" (Printexc.exn_slot_name ex)));
      check_int "finished release defect entered once" 1 !defects;
      (match
         Resource.use_in_scope
           ~sw:(Scope.switch (Option.get !finished))
           (fun () -> ())
           (fun () ->
             incr defects;
             raise Boom)
       with
      | () -> Alcotest.fail "finished resource release defect must propagate"
      | exception ex ->
          check_bool "Eio wraps immediate release defect" true
            (String.ends_with ~suffix:"Switch.Release_error" (Printexc.exn_slot_name ex)));
      check_int "finished resource release defect entered once" 2 !defects)

let fork_cancellation () =
  Eio_mock.Backend.run (fun () ->
      let entered = ref 0 and cleaned = ref 0 and released = ref 0 in
      let ready, resolve = Eio.Promise.create () in
      let result =
        Eio.Switch.run (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                Scope.on_release scope (fun () -> incr released);
                Scope.fork scope (fun () ->
                    incr entered;
                    Eio.Promise.resolve resolve ();
                    Fun.protect Eio.Fiber.await_cancel ~finally:(fun () -> incr cleaned));
                Eio.Promise.await ready;
                Error "stop"))
      in
      check_bool "typed cancellation unchanged" true (result = Error "stop");
      check_int "entered once" 1 !entered;
      check_int "cleanup awaited" 1 !cleaned;
      check_int "release once" 1 !released)

let branches () =
  Eio_mock.Backend.run (fun () ->
      Eio.Switch.run (fun sw ->
          check_bool "all order" true
            (Concurrent.all ~sw [ (fun () -> Ok 1); (fun () -> Ok 2) ] = Ok [ 1; 2 ]);
          check_bool "empty all" true (Concurrent.all ~sw [] = Ok []);
          check_bool "race succeeds after typed failure" true
            (Concurrent.race ~sw [ (fun () -> Error "no"); (fun () -> Ok 3) ] = Ok 3);
          check_bool "race_first preserves outcome" true
            (Concurrent.race_first ~sw [ (fun () -> Error "first") ] = Error "first");
          let calls = ref 0 in
          check_bool "mapper reused per item" true
            (Concurrent.for_each ~sw ~concurrency:2 [ 1; 2; 3 ] (fun x ->
                 incr calls;
                 Ok (x * 2))
            = Ok [ 2; 4; 6 ]);
          check_int "many mapper enters three times" 3 !calls;
          let ready, resolve = Eio.Promise.create () in
          let cleaned = ref 0 in
          let result =
            Concurrent.both ~sw
              (fun () ->
                Eio.Promise.resolve resolve ();
                Fun.protect Eio.Fiber.await_cancel ~finally:(fun () -> incr cleaned))
              (fun () ->
                Eio.Promise.await ready;
                Error "fail")
          in
          check_bool "typed fail-fast preserved" true (result = Error "fail");
          check_int "loser cleanup awaited" 1 !cleaned))

let local_callbacks () =
  Eio_mock.Backend.run_full (fun env ->
      Eio.Switch.run (fun sw ->
          let attempts = ref 0 and calls = ref 0 in
          let limiter =
            Rate_limiter.create ~sw ~clock:env#mono_clock
              (Custom
                 (fun ~now_ms ->
                   check_int "custom retains zero local origin" 0 now_ms;
                   {
                     try_acquire =
                       (fun ~now_ms:_ ->
                         incr attempts;
                         if !attempts < 3 then Wait (Duration.ms 1) else Granted);
                   }))
          in
          check_bool "drop does not enter callback" true
            (Rate_limiter.run_or_drop limiter (fun () -> incr calls) = None);
          check_int "dropped callback" 0 !calls;
          check_int "wait result" 7
            (Rate_limiter.run limiter (fun () ->
                 incr calls;
                 7));
          check_int "wait callback enters once" 1 !calls;
          check_int "permit attempted three times" 3 !attempts;
          let acquired = ref 0 and released = ref 0 in
          let ready, resolve = Eio.Promise.create () in
          Eio.Fiber.first
            (fun () ->
              Resource.use_in_scope ~sw
                (fun () ->
                  incr acquired;
                  Eio.Promise.resolve resolve ();
                  Eio.Fiber.await_cancel ())
                (fun () -> incr released))
            (fun () -> Eio.Promise.await ready);
          check_int "cancelled acquire enters once" 1 !acquired;
          check_int "cancelled acquire registers no release" 0 !released))

let () =
  Alcotest.run "Once prerequisite"
    [
      ( "guard",
        [
          Alcotest.test_case "^nonce-ldtz result and affine drop" `Quick guard_result;
          Alcotest.test_case "^nonce-ldtz defect" `Quick guard_defect;
          Alcotest.test_case "^nonce-ldtz reentrant" `Quick guard_reentrant;
          Alcotest.test_case "^nonce-ldtz atomic domains" `Quick guard_domains;
          Alcotest.test_case "^nonce-ldtz cancellation" `Quick guard_cancel;
        ] );
      ( "wrappers",
        [
          Alcotest.test_case "^nonce-4jzx releases" `Quick releases;
          Alcotest.test_case "^nonce-r7mi fork cancellation" `Quick fork_cancellation;
          Alcotest.test_case "^nonce-nngp branch cancellation and mapper" `Quick branches;
          Alcotest.test_case "^nonce-lrzq in-place and cancelled acquire" `Quick
            local_callbacks;
        ] );
    ]
