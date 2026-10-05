(* ^nparse-gb03: public checked bounds preserve physical native ownership. *)
open Ox_blocking

let require name condition = if not condition then failwith name
let inc count = ignore (Atomic.fetch_and_add count 1)

let concurrency value =
  match Ox.Concurrency.of_int value with
  | Ok bound -> bound
  | Error `Invalid -> failwith "invalid runtime fixture concurrency"

let checked_construction () =
  List.iter
    (fun value ->
      match Ox.Concurrency.of_int value with
      | Error `Invalid -> ()
      | Ok _ -> failwith "nonpositive worker concurrency accepted")
    [ min_int; -1; 0 ];
  List.iter
    (fun value ->
      match Ox.Concurrency.of_int value with
      | Ok bound -> require "concurrency round trip" (Ox.Concurrency.to_int bound = value)
      | Error `Invalid -> failwith "positive worker concurrency rejected")
    [ 1; 2; max_int ]

let with_gate ~releases f =
  Eio_main.run (fun env ->
      let gate = Semaphore.Counting.make 0 in
      Eio.Switch.run (fun sw ->
          Fun.protect
            ~finally:(fun () ->
              for _ = 1 to releases do
                Semaphore.Counting.release gate
              done)
            (fun () -> Eio.Time.with_timeout_exn env#clock 5. (fun () -> f env sw gate))))

let rec peak count value =
  let previous = Atomic.get count in
  if value > previous && not (Atomic.compare_and_set count previous value) then
    peak count value

let rec wait_until clock predicate =
  if not (predicate ()) then (
    Eio.Time.Mono.sleep clock 0.001;
    wait_until clock predicate)

let worker_limit limit =
  let jobs = limit + 3 in
  with_gate ~releases:jobs (fun env sw gate ->
      let pool =
        Pool.create ~sw
          {
            max_threads = concurrency limit;
            max_queued = 1;
            shutdown_policy = Pool.Drain;
          }
      in
      let started = Eio.Semaphore.make 0 in
      let active = Atomic.make 0 in
      let maximum = Atomic.make 0 in
      let calls =
        List.init jobs (fun value ->
            Eio.Fiber.fork_promise ~sw (fun () ->
                run ~pool (fun () ->
                    let running = Atomic.fetch_and_add active 1 + 1 in
                    peak maximum running;
                    Eio.Semaphore.release started;
                    Fun.protect
                      ~finally:(fun () -> ignore (Atomic.fetch_and_add active (-1)))
                      (fun () ->
                        Semaphore.Counting.acquire gate;
                        value))))
      in
      for _ = 1 to limit do
        Eio.Semaphore.acquire started
      done;
      wait_until env#mono_clock (fun () -> (Pool.stats pool).queued = 1);
      require "physical callbacks reach exactly the checked limit"
        (Atomic.get active = limit);
      require "pool active count reaches exactly the checked limit"
        ((Pool.stats pool).active = limit);
      (match try_run ~pool (fun () -> failwith "saturated callback executed") with
      | Not_run Saturated -> ()
      | _ -> failwith "pool did not enforce the checked worker limit");
      for _ = 1 to jobs do
        Semaphore.Counting.release gate
      done;
      List.iteri
        (fun expected promise ->
          match Eio.Promise.await_exn promise with
          | Ok value -> require "worker result retained" (value = expected)
          | Error `Shutting_down -> failwith "open pool rejected an admitted worker")
        calls;
      Pool.shutdown pool;
      let stats = Pool.stats pool in
      require "native callbacks never exceed the checked worker limit"
        (Atomic.get maximum = limit);
      require "all native callbacks physically returned" (Atomic.get active = 0);
      require "all physical completions are accounted" (stats.completed = jobs);
      require "pool counts settle to zero"
        (stats.active = 0 && stats.queued = 0 && stats.waiting = 0))

let worker_limits () = List.iter worker_limit [ 1; 2; 4 ]

let cancelled_worker () =
  with_gate ~releases:1 (fun _ sw gate ->
      let pool =
        Pool.create ~sw
          { max_threads = concurrency 1; max_queued = 0; shutdown_policy = Pool.Drain }
      in
      let started = Eio.Semaphore.make 0 in
      let settled = Atomic.make 0 in
      let cancelled = Atomic.make 0 in
      let context = ref None in
      let caller =
        Eio.Fiber.fork_promise ~sw (fun () ->
            Eio.Cancel.sub (fun cancel ->
                context := Some cancel;
                match
                  run_leased_result ~pool
                    ~on_cancel:(fun () -> inc cancelled)
                    ~release:(function
                      | Settled (Ok (Ok 7)) -> inc settled
                      | _ -> failwith "claimed native worker did not physically settle")
                    (fun () ->
                      Eio.Semaphore.release started;
                      Semaphore.Counting.acquire gate;
                      Ok 7)
                with
                | _ -> false
                | exception Eio.Cancel.Cancelled _ -> true))
      in
      Eio.Semaphore.acquire started;
      (match !context with
      | Some cancel -> Eio.Cancel.cancel cancel (Failure "cancel worker caller")
      | None -> failwith "worker cancellation context missing");
      require "caller observes its cancellation" (Eio.Promise.await_exn caller);
      require "cancel hook runs once" (Atomic.get cancelled = 1);
      require "lease has not settled before native return" (Atomic.get settled = 0);
      require "cancelled native callback still holds physical capacity"
        ((Pool.stats pool).active = 1);
      (match
         try_run ~pool (fun () -> failwith "cancelled worker's slot reused early")
       with
      | Not_run Saturated -> ()
      | _ -> failwith "caller cancellation released physical worker capacity");
      let drain = Eio.Fiber.fork_promise ~sw (fun () -> Pool.shutdown pool) in
      Eio.Fiber.yield ();
      require "Drain waits for native completion" (not (Eio.Promise.is_resolved drain));
      Semaphore.Counting.release gate;
      Eio.Promise.await_exn drain;
      let stats = Pool.stats pool in
      require "lease settles exactly once after native return" (Atomic.get settled = 1);
      require "cancelled physical completion is counted" (stats.completed = 1);
      require "claimed cancellation is not preclaim cancellation"
        (stats.cancelled_before_start = 0);
      require "cancelled worker finally releases its physical slot" (stats.active = 0))

let queue_boundary () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let config max_queued =
            { Pool.max_threads = concurrency 1; max_queued; shutdown_policy = Pool.Drain }
          in
          (match Pool.create ~sw (config (-1)) with
          | exception Invalid_argument message ->
              require "negative queue diagnostic unchanged"
                (message = "Ox_blocking.Pool.create: invalid limits")
          | _ -> failwith "negative waiting queue admitted");
          let pool = Pool.create ~sw (config 0) in
          (match run ~pool (fun () -> 7) with
          | Ok 7 -> ()
          | _ -> failwith "zero waiting queue rejected an available worker");
          Pool.shutdown pool;
          require "zero-queue completion accounted" ((Pool.stats pool).completed = 1)))

let run () =
  checked_construction ();
  worker_limits ();
  cancelled_worker ();
  queue_boundary ()
