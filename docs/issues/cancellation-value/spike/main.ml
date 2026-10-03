open Ox
let passed = ref 0
let expect condition = if not condition then failwith "assertion failed"
let canceled = function Error `Canceled -> true | _ -> false
let test name f =
  f (); incr passed; Printf.printf "PASS %s\n%!" name
let pp_error fmt _ = Format.pp_print_string fmt "typed"
let catch_cancel reason f =
  try ignore (f ()); false with Eio.Cancel.Cancelled ex -> ex == reason
let run env =
  let clock = env#clock in
  test "pre-canceled receive is a value, broad handler does not intercept" (fun () ->
    Cancellation.with_ (fun cancel ->
      Cancellation.Source.cancel (Cancellation.source cancel);
      let caught = ref false in
      let result = try Channel.receive ~cancel (Channel.create ()) with _ -> caught := true; Error `Done in
      expect (canceled result && not !caught);
      Eio.Fiber.yield ()));
  test "blocked receive wakes on explicit source cancellation" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 0.001; Cancellation.Source.cancel source);
        expect (canceled (Channel.receive ~cancel (Channel.create ()))))));
  test "normal payload, Done, and channel error remain unchanged" (fun () ->
    Cancellation.with_ (fun cancel ->
      let channel = Channel.create () in
      expect (Channel.send channel 42 = Ok ());
      expect (Channel.receive ~cancel channel = Ok 42);
      Channel.done_ channel; expect (Channel.receive ~cancel channel = Error `Done);
      let channel = Channel.create () in
      Channel.error channel `Oops;
      expect (Channel.receive ~cancel channel = Error (`Error `Oops))));
  test "canceled token does not consume a queued item" (fun () ->
    let channel = Channel.create () in
    expect (Channel.send channel 7 = Ok ());
    Cancellation.with_ (fun cancel ->
      Cancellation.Source.cancel (Cancellation.source cancel);
      expect (canceled (Channel.receive ~cancel channel)));
    Cancellation.with_ (fun cancel -> expect (Channel.receive ~cancel channel = Ok 7)));
  test "same source wakes multiple receivers through per-fiber local borrows" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        let count = ref 0 in
        let channel = Channel.create () in
        for _ = 1 to 2 do
          Eio.Fiber.fork ~sw (fun () ->
            Cancellation.with_source source (fun cancel ->
              expect (canceled (Channel.receive ~cancel channel)); incr count))
        done;
        Eio.Fiber.yield (); Cancellation.Source.cancel source;
        while !count <> 2 do Eio.Fiber.yield () done)));
  test "Scope.supervised_error returns Error Canceled and joins sibling cleanup" (fun () ->
    let cleaned = ref false in
    let outcome = Scope.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        let result = Scope.supervised_error ~sw (fun scope ->
          ignore (Scope.fork_error scope (fun () ->
            Cancellation.with_source source (fun cancel -> Channel.receive ~cancel (Channel.create ()))));
          Scope.fork scope (fun () ->
            Fun.protect ~finally:(fun () -> cleaned := true) Eio.Fiber.await_cancel);
          Scope.fork scope (fun () -> Eio.Time.sleep clock 0.001; Cancellation.Source.cancel source);
          Eio.Fiber.await_cancel ()) in
        expect !cleaned; result)) in
    expect (match outcome with Exit.Failure (Cause.Fail `Canceled) -> true | _ -> false));
  test "Concurrent.par returns Error Canceled and joins the canceled sibling" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 0.001; Cancellation.Source.cancel source);
        let cleaned = ref false in
        let result = Concurrent.par ~sw
          (fun () -> Cancellation.with_source source (fun cancel -> Channel.receive ~cancel (Channel.create ())))
          (fun () -> Fun.protect ~finally:(fun () -> cleaned := true) Eio.Fiber.await_cancel) in
        expect (canceled result && !cleaned))));
  test "Concurrent.race ignores Canceled failure in favor of success" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        Cancellation.Source.cancel source;
        let result = Concurrent.race ~sw [
          (fun () -> Cancellation.with_source source (fun cancel -> Channel.receive ~cancel (Channel.create ())));
          (fun () -> Eio.Time.sleep clock 0.001; Ok 11)] in
        expect (result = Ok 11))));
  test "Concurrent.race aggregates all Canceled failures as Cause.Fail" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        Cancellation.Source.cancel source;
        let branch () = Cancellation.with_source source (fun cancel -> Channel.receive ~cancel (Channel.create ())) in
        let result = Concurrent.race ~sw [branch; branch] in
        expect (match result with Error (Cause.Concurrent [Cause.Fail `Canceled; Cause.Fail `Canceled]) -> true | _ -> false))));
  test "parent cancellation remains the original Eio exception" (fun () ->
    let reason = Failure "parent" in
    expect (catch_cancel reason (fun () ->
      Eio.Cancel.sub (fun cc ->
        Eio.Switch.run (fun sw ->
          Cancellation.with_ (fun cancel ->
            Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 0.001; Eio.Cancel.cancel cc reason);
            Channel.receive ~cancel (Channel.create ())))))));
  test "parent termination wins over token cancellation in the same scheduler turn" (fun () ->
    let reason = Failure "both" in
    expect (catch_cancel reason (fun () ->
      Eio.Cancel.sub (fun cc ->
        Eio.Switch.run (fun sw ->
          Cancellation.with_ (fun cancel ->
            let source = Cancellation.source cancel in
            Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.sleep clock 0.001;
              Cancellation.Source.cancel source; Eio.Cancel.cancel cc reason);
            Channel.receive ~cancel (Channel.create ())))))));
  test "sibling defect stays Die, never Canceled" (fun () ->
    let boom = Failure "sibling defect" in
    let outcome = Scope.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 0.001; raise boom);
        Channel.receive ~cancel (Channel.create ()))) in
    expect (match outcome with Exit.Failure (Cause.Die (ex, _)) -> ex == boom | _ -> false));
  test "race-loser receive still raises Eio cancellation; winner survives" (fun () ->
    Eio.Switch.run (fun sw ->
      let interrupted = ref false in
      let result = Concurrent.race ~sw [
        (fun () -> Cancellation.with_ (fun cancel ->
          try Channel.receive ~cancel (Channel.create ())
          with Eio.Cancel.Cancelled _ as ex -> interrupted := true; raise ex));
        (fun () -> Eio.Time.sleep clock 0.001; Ok 12)] in
      expect (result = Ok 12 && !interrupted)));
  test "existing Timeout still returns typed Timeout" (fun () ->
    expect (Timeout.timeout ~clock (Duration.ms 1) (fun () ->
      Cancellation.with_ (fun cancel -> Channel.receive ~cancel (Channel.create ()))) = Error `Timeout));
  test "named receive under an explicit source deadline returns Canceled" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 0.001; Cancellation.Source.cancel source);
        expect (canceled (Channel.receive ~cancel (Channel.create ()))))));
  test "source cancellation does not cancel unrelated ambient Eio work" (fun () ->
    Eio.Switch.run (fun sw ->
      Cancellation.with_ (fun cancel ->
        let source = Cancellation.source cancel in
        Eio.Fiber.fork ~sw (fun () -> Eio.Time.sleep clock 0.001; Cancellation.Source.cancel source);
        Eio.Time.sleep clock 0.003;
        expect (Cancellation.is_canceled cancel);
        Eio.Fiber.check ())));
  test "escaped source rejected after with_ returns" (fun () ->
    let source = Cancellation.with_ Cancellation.source in
    expect (try Cancellation.Source.cancel source; false with Invalid_argument _ -> true));
  test "wide handler can still swallow implicit termination" (fun () ->
    let reason = Failure "termination" in
    let value = Eio.Cancel.sub (fun cc ->
      Cancellation.with_ (fun cancel ->
        Eio.Cancel.cancel cc reason;
        try ignore (Channel.receive ~cancel (Channel.create ())); "wrong"
        with _ -> "swallowed")) in
    expect (value = "swallowed"));
  Printf.printf "RESULT %d/%d runtime checks passed\n%!" !passed !passed
let () = Printexc.record_backtrace true; Eio_main.run run
