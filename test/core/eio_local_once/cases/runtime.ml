(* Bounded single-domain native provider controls. No shim or locality cast. ^nonce-lrzq ^nonce-mjpe *)
exception Marker
let check condition message = if not condition then failwith message
let expect_cancel (fn @ local once) =
  match fn () with
  | exception Eio.Cancel.Cancelled Marker -> ()
  | _ -> failwith "expected native parent cancellation"
let expect_poison (fn @ local once) =
  match fn () with
  | exception Eio.Mutex.Poisoned Marker -> ()
  | _ -> failwith "expected native mutex poisoning"
type payload = { text : bytes; link : string ref }
type holder = { payload : payload @@ global }
let make_payload () = { text = Bytes.make 8192 'q'; link = ref (String.make 4096 'r') }
let validate payload =
  check (Bytes.length payload.text = 8192 && Bytes.get payload.text 8191 = 'q') "heap bytes lost";
  check (String.length !(payload.link) = 4096 && !(payload.link).[4095] = 'r') "transitive heap graph lost"
let collect () =
  for _ = 1 to 3 do
    for _ = 1 to 64 do ignore (Bytes.make 4096 'x') done;
    Gc.full_major ()
  done
let local_protect_gc () =
  let holder = stack_ { payload = make_payload () } in
  let callback = stack_ (fun () -> Eio.Fiber.yield (); collect (); validate holder.payload; 42) in
  check ((Eio.Cancel.protect callback [@nontail]) = 42) "local protect result"
let protect_restores_normal () =
  Eio.Cancel.sub (fun parent ->
    let holder = stack_ { payload = make_payload () } in
    let callback = stack_ (fun () ->
      Eio.Cancel.cancel parent Marker;
      Eio.Fiber.yield (); Eio.Fiber.check (); collect (); validate holder.payload; 42) in
    check ((Eio.Cancel.protect callback [@nontail]) = 42) "shielded return";
    expect_cancel Eio.Fiber.check)
let protect_restores_exception () =
  Eio.Cancel.sub (fun parent ->
    let holder = stack_ { payload = make_payload () } in
    let callback = stack_ (fun () -> Eio.Fiber.yield (); validate holder.payload; raise Marker) in
    (match (Eio.Cancel.protect callback [@nontail]) with
     | exception Marker -> () | _ -> failwith "protected defect lost");
    Eio.Fiber.check ();
    Eio.Cancel.cancel parent Marker;
    expect_cancel Eio.Fiber.check)
let nested_protect () =
  Eio.Cancel.sub (fun parent ->
    let holder = stack_ { payload = make_payload () } in
    let outer = stack_ (fun () ->
      let inner = stack_ (fun () -> Eio.Cancel.cancel parent Marker; Eio.Fiber.yield (); validate holder.payload) in
      Eio.Cancel.protect inner [@nontail];
      Eio.Fiber.check (); collect (); validate holder.payload; 42) in
    check ((Eio.Cancel.protect outer [@nontail]) = 42) "nested shield";
    expect_cancel Eio.Fiber.check)
let queued_gc protect () =
  for _ = 1 to 24 do
    let mutex = Eio.Mutex.create () in
    let witness = Weak.create 1 in
    let ready, signal_ready = Eio.Promise.create () in
    let done_, signal_done = Eio.Promise.create () in
    let calls = ref 0 in
    Eio.Switch.run (fun sw ->
      Eio.Mutex.lock mutex;
      Eio.Fiber.fork ~sw (fun () ->
        let holder = stack_ { payload = make_payload () } in
        Weak.set witness 0 (Some holder.payload);
        let callback = stack_ (fun () -> incr calls; collect (); validate holder.payload; 42) in
        Eio.Promise.resolve signal_ready ();
        let value = Eio.Mutex.use_rw ~protect mutex callback [@nontail] in
        Eio.Promise.resolve signal_done value);
      Eio.Promise.await ready;
      check (!calls = 0 && not (Eio.Promise.is_resolved done_)) "callback entered before queued-GC check";
      collect ();
      check (Weak.check witness 0) "only local closure graph root lost before lock entry";
      Eio.Mutex.unlock mutex;
      check (Eio.Promise.await done_ = 42 && !calls = 1) "queued callback not exactly once");
    collect ();
    check (not (Weak.check witness 0)) "graph unexpectedly retained after local activation returns"
  done
let cancelled_acquisition protect () =
  let mutex = Eio.Mutex.create () in
  let ready, signal_ready = Eio.Promise.create () in
  let done_, signal_done = Eio.Promise.create () in
  let witness = Weak.create 1 in
  let calls = ref 0 in
  Eio.Switch.run (fun sw ->
    Eio.Mutex.lock mutex;
    Eio.Fiber.fork ~sw (fun () ->
      Eio.Cancel.sub (fun context ->
        let holder = stack_ { payload = make_payload () } in
        Weak.set witness 0 (Some holder.payload);
        let callback = stack_ (fun () -> incr calls; validate holder.payload) in
        Eio.Promise.resolve signal_ready context;
        (expect_cancel (fun () -> Eio.Mutex.use_rw ~protect mutex callback [@nontail]) [@nontail]));
      Eio.Promise.resolve signal_done ());
    let context = Eio.Promise.await ready in
    check (!calls = 0) "acquisition callback entered while lock held";
    collect (); check (Weak.check witness 0) "cancel queue root lost";
    Eio.Cancel.cancel context Marker;
    Eio.Promise.await done_;
    check (!calls = 0) "cancelled acquisition invoked callback";
    Eio.Mutex.unlock mutex);
  check (Eio.Mutex.use_rw ~protect:true mutex (fun () -> 42) = 42) "cancelled acquisition poisoned mutex"
let shielded_rw () =
  let mutex = Eio.Mutex.create () in
  let ready, signal_ready = Eio.Promise.create () in
  let gate, open_gate = Eio.Promise.create () in
  let done_, signal_done = Eio.Promise.create () in
  let calls = ref 0 in
  Eio.Switch.run (fun sw ->
    Eio.Fiber.fork ~sw (fun () ->
      Eio.Cancel.sub (fun parent ->
        let holder = stack_ { payload = make_payload () } in
        let callback = stack_ (fun () ->
          incr calls; Eio.Promise.resolve signal_ready parent;
          Eio.Promise.await gate; Eio.Fiber.check (); collect (); validate holder.payload; 42) in
        check ((Eio.Mutex.use_rw ~protect:true mutex callback [@nontail]) = 42) "shielded critical return";
        expect_cancel Eio.Fiber.check);
      Eio.Promise.resolve signal_done ());
    let parent = Eio.Promise.await ready in
    Eio.Cancel.cancel parent Marker; Eio.Fiber.yield ();
    check (not (Eio.Promise.is_resolved done_)) "protected critical section cancelled";
    Eio.Promise.resolve open_gate (); Eio.Promise.await done_);
  check (!calls = 1) "shielded callback count";
  check (Eio.Mutex.use_rw ~protect:false mutex (fun () -> 42) = 42) "normal shielded RW poisoned"
let poison_wakes_waiters () =
  let mutex = Eio.Mutex.create () in
  let entered, signal_entered = Eio.Promise.create () in
  let gate, open_gate = Eio.Promise.create () in
  let poisoned = ref 0 and waiter_calls = ref 0 in
  let witnesses = Array.init 2 (fun _ -> Weak.create 1) in
  Eio.Switch.run (fun sw ->
    Eio.Fiber.fork ~sw (fun () ->
      let holder = stack_ { payload = make_payload () } in
      let callback = stack_ (fun () -> Eio.Promise.resolve signal_entered (); Eio.Promise.await gate; validate holder.payload; raise Marker) in
      (match (Eio.Mutex.use_rw ~protect:true mutex callback [@nontail]) with
       | exception Marker -> () | _ -> failwith "critical defect lost"));
    Eio.Promise.await entered;
    for index = 0 to 1 do
      Eio.Fiber.fork ~sw (fun () ->
        let holder = stack_ { payload = make_payload () } in
        Weak.set witnesses.(index) 0 (Some holder.payload);
        let callback = stack_ (fun () -> incr waiter_calls; validate holder.payload) in
        (match (Eio.Mutex.use_rw ~protect:true mutex callback [@nontail]) with
         | exception Eio.Mutex.Poisoned Marker -> incr poisoned
         | _ -> failwith "poisoned waiter did not receive cause"))
    done;
    Eio.Fiber.yield (); collect ();
    check (Array.for_all (fun witness -> Weak.check witness 0) witnesses) "poison queue local root lost";
    check (!waiter_calls = 0) "poison waiters entered";
    Eio.Promise.resolve open_gate ());
  check (!poisoned = 2 && !waiter_calls = 0) "poison wakeup/drop counts";
  expect_poison (fun () -> Eio.Mutex.use_rw ~protect:true mutex (fun () -> ()))
let successful_wakeups () =
  let mutex = Eio.Mutex.create () in
  let calls = Array.make 3 0 in
  Eio.Switch.run (fun sw ->
    Eio.Mutex.lock mutex;
    for index = 0 to 2 do
      Eio.Fiber.fork ~sw (fun () ->
        let holder = stack_ { payload = make_payload () } in
        let callback = stack_ (fun () -> calls.(index) <- calls.(index) + 1; Eio.Fiber.yield (); validate holder.payload) in
        Eio.Mutex.use_rw ~protect:true mutex callback [@nontail])
    done;
    Eio.Fiber.yield (); collect (); Eio.Mutex.unlock mutex);
  check (Array.for_all ((=) 1) calls) "successful lock handoff callbacks not once"
let unprotected_body_cancel_poison () =
  let mutex = Eio.Mutex.create () in
  let ready, signal_ready = Eio.Promise.create () in
  let done_, signal_done = Eio.Promise.create () in
  let calls = ref 0 in
  Eio.Switch.run (fun sw ->
    Eio.Fiber.fork ~sw (fun () ->
      Eio.Cancel.sub (fun context ->
        let holder = stack_ { payload = make_payload () } in
        let callback = stack_ (fun () -> incr calls; validate holder.payload; Eio.Promise.resolve signal_ready context; Eio.Fiber.await_cancel ()) in
        (expect_cancel (fun () -> Eio.Mutex.use_rw ~protect:false mutex callback [@nontail]) [@nontail]));
      Eio.Promise.resolve signal_done ());
    let context = Eio.Promise.await ready in
    collect (); Eio.Cancel.cancel context Marker; Eio.Promise.await done_);
  check (!calls = 1) "unprotected callback count";
  (match Eio.Mutex.use_rw ~protect:false mutex (fun () -> ()) with
   | exception Eio.Mutex.Poisoned (Eio.Cancel.Cancelled Marker) -> ()
   | _ -> failwith "unprotected cancellation did not poison")
let repeated_global () =
  let calls = ref 0 in
  let callback () = incr calls; 42 in
  let mutex = Eio.Mutex.create () in
  for _ = 1 to 12 do
    check (Eio.Cancel.protect callback = 42) "global protect compatibility";
    check (Eio.Mutex.use_rw ~protect:true mutex callback = 42) "global mutex compatibility"
  done;
  check (!calls = 24 && callback () = 42 && !calls = 25) "many global callback reuse"
let tests = [
  "paired physical-local unique callers", (fun () -> check (Good_z_physical_callers.run (Eio.Mutex.create ()) = 126) "paired local unique results");
  "physical-local protect/GC", local_protect_gc;
  "native shield + normal context restoration", protect_restores_normal;
  "native exceptional context restoration", protect_restores_exception;
  "nested shields", nested_protect;
  "queued protected physical-local graph/GC/release", queued_gc true;
  "queued unprotected physical-local graph/GC/release", queued_gc false;
  "protected acquisition remains cancellable/drop", cancelled_acquisition true;
  "unprotected acquisition remains cancellable/drop", cancelled_acquisition false;
  "protected RW body survives parent cancellation", shielded_rw;
  "RW native poison/wakeup/drop", poison_wakes_waiters;
  "RW successful handoff", successful_wakeups;
  "unprotected RW cancellation poisons", unprotected_body_cancel_poison;
  "global many compatibility/repeated providers", repeated_global;
]
