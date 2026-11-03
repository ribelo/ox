(* ^ncrit-ihf2 ^ncrit-9sfw: lock exclusion, release on exception and on cancellation. *)

exception Boom

let check_int = Alcotest.(check int)

module Counter : sig
  type 'k t

  val make : 'k Ox.Mutex.t -> 'k t
  val incr : 'k Ox.Mutex.Access.t @ local -> 'k t -> unit
  val get : 'k Ox.Mutex.Access.t @ local -> 'k t -> int
end = struct
  type 'k t = { mutable n : int }

  let make _ = { n = 0 }
  let incr _ t = t.n <- t.n + 1
  let get _ t = t.n
end

let exclusion () =
  Eio_mock.Backend.run (fun () ->
      let (Ox.Mutex.P m) = Ox.Mutex.create () in
      let c = Counter.make m in
      let inside = ref 0 and most = ref 0 in
      let section () =
        Ox.Mutex.with_access_waiting m (fun a ->
            incr inside;
            most := max !most !inside;
            Eio.Fiber.yield ();
            Counter.incr a c;
            decr inside)
      in
      Eio.Fiber.all [ section; section; section ];
      check_int "one fiber inside at a time" 1 !most;
      check_int "every section ran" 3 (Ox.Mutex.with_access m (fun a -> Counter.get a c)))

let released_on_exception () =
  Eio_mock.Backend.run (fun () ->
      let (Ox.Mutex.P m) = Ox.Mutex.create () in
      let c = Counter.make m in
      (match
         Ox.Mutex.with_access m (fun a ->
             Counter.incr a c;
             raise Boom)
       with
      | () -> Alcotest.fail "the defect must propagate"
      | exception Boom -> ());
      check_int "lock released, change kept" 1
        (Ox.Mutex.with_access m (fun a -> Counter.get a c)))

let released_on_cancellation () =
  Eio_mock.Backend.run (fun () ->
      let (Ox.Mutex.P m) = Ox.Mutex.create () in
      let c = Counter.make m in
      let entered, entered_u = Eio.Promise.create () in
      Eio.Fiber.first
        (fun () ->
          Ox.Mutex.with_access_waiting m (fun a ->
              Counter.incr a c;
              Eio.Promise.resolve entered_u ();
              Eio.Fiber.await_cancel ()))
        (fun () -> Eio.Promise.await entered);
      check_int "cancelled section released the lock" 1
        (Ox.Mutex.with_access m (fun a -> Counter.get a c)))

let cancelled_acquisition () =
  Eio_mock.Backend.run (fun () ->
      let (Ox.Mutex.P m) = Ox.Mutex.create () in
      let c = Counter.make m in
      let holding, holding_u = Eio.Promise.create () in
      let finish, finish_u = Eio.Promise.create () in
      let entered = ref 0 in
      Eio.Fiber.both
        (fun () ->
          Ox.Mutex.with_access_waiting m (fun a ->
              Eio.Promise.resolve holding_u ();
              Eio.Promise.await finish;
              Counter.incr a c))
        (fun () ->
          Eio.Promise.await holding;
          Eio.Fiber.first
            (fun () -> Ox.Mutex.with_access m (fun a -> incr entered; Counter.incr a c))
            (fun () -> ());
          Eio.Promise.resolve finish_u ());
      check_int "a cancelled waiter never enters" 0 !entered;
      check_int "the holder finished" 1 (Ox.Mutex.with_access m (fun a -> Counter.get a c)))

let try_when_held () =
  Eio_mock.Backend.run (fun () ->
      let (Ox.Mutex.P m) = Ox.Mutex.create () in
      let c = Counter.make m in
      let held =
        Ox.Mutex.with_access m (fun _ ->
            Ox.Mutex.try_with_access_waiting m (fun a -> Counter.incr a c))
      in
      (match held with Some () -> Alcotest.fail "a held mutex must refuse" | None -> ());
      (match Ox.Mutex.try_with_access_waiting m (fun a -> Counter.incr a c) with
      | Some () -> ()
      | None -> Alcotest.fail "a free mutex must enter");
      check_int "entered once" 1 (Ox.Mutex.with_access m (fun a -> Counter.get a c)))

let protected_acquisition () =
  Eio_mock.Backend.run (fun () ->
      let (Ox.Mutex.P m) = Ox.Mutex.create () in
      let c = Counter.make m in
      let holding, holding_u = Eio.Promise.create () in
      let finish, finish_u = Eio.Promise.create () in
      Eio.Fiber.both
        (fun () ->
          Ox.Mutex.with_access_waiting m (fun _ ->
              Eio.Promise.resolve holding_u ();
              Eio.Promise.await finish))
        (fun () ->
          Eio.Promise.await holding;
          Eio.Fiber.first
            (fun () ->
              Ox.Mutex.with_access_protected m (fun a -> Counter.incr a c);
              Eio.Fiber.yield ())
            (fun () -> Eio.Promise.resolve finish_u ()));
      check_int "a shielded waiter still enters" 1
        (Ox.Mutex.with_access m (fun a -> Counter.get a c)))

let () =
  Alcotest.run "Ox.Mutex"
    [
      ( "sections",
        [
          Alcotest.test_case "^ncrit-ihf2 exclusion" `Quick exclusion;
          Alcotest.test_case "^ncrit-ihf2 released on exception" `Quick released_on_exception;
          Alcotest.test_case "^ncrit-9sfw released on cancellation" `Quick
            released_on_cancellation;
          Alcotest.test_case "^ncrit-ihf2 cancelled acquisition" `Quick cancelled_acquisition;
          Alcotest.test_case "^ncrit-9sfw try when held" `Quick try_when_held;
          Alcotest.test_case "^ncrit-9sfw protected acquisition" `Quick protected_acquisition;
        ] );
    ]
