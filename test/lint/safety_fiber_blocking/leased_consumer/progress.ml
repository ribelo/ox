(* ^safe-9ved ^safe-r5ye: genuine installed native acquire cannot stall owner progress. *)
let () =
  let owner = Array.exists (( = ) "--owner") Sys.argv in
  Eio_main.run (fun env ->
      let clock = Eio.Stdenv.clock env in
      Eio.Switch.run (fun sw ->
          let bound =
            match Ox.Concurrency.of_int 1 with
            | Ok value -> value
            | Error _ -> failwith "invalid literal bound"
          in
          let config : Ox_blocking.Pool.config =
            { max_threads = bound; max_queued = 1; shutdown_policy = Drain }
          in
          let pool = Ox_blocking.Pool.create ~sw config in
          let semaphore = Semaphore.Counting.make 0 in
          let started = Atomic.make false and completed = Atomic.make false in
          let advanced = ref false in
          let job () =
            Atomic.set started true;
            Semaphore.Counting.acquire semaphore;
            Atomic.set completed true
          in
          Eio.Time.with_timeout_exn clock 2. (fun () ->
              Eio.Fiber.both
                (fun () ->
                  if owner then job ()
                  else
                    match Ox_blocking.run ~pool job with
                    | Ok () -> ()
                    | Error _ -> failwith "native wait failed")
                (fun () ->
                  Fun.protect
                    ~finally:(fun () -> Semaphore.Counting.release semaphore)
                    (fun () ->
                      let rec await_start () =
                        if not (Atomic.get started) then (
                          Eio.Time.sleep clock 0.001;
                          await_start ())
                      in
                      await_start ();
                      if Atomic.get completed then
                        failwith "native semaphore did not retain the wait";
                      advanced := true)));
          assert (!advanced && Atomic.get completed);
          Ox_blocking.Pool.shutdown pool))
