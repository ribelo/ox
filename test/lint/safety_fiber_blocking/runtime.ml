(* ^safe-9ved ^safe-r5ye: runtime proof at Eio and public Ox_blocking seams. *)
let witness clock pause =
  let completed = ref false and advanced = ref false in
  Eio.Fiber.both
    (fun () ->
      pause ();
      completed := true)
    (fun () ->
      Eio.Time.sleep clock 0.001;
      if !completed then failwith "safe-9ved: synchronous wait stalled unrelated fiber";
      advanced := true);
  assert (!completed && !advanced)

let () =
  Eio_main.run (fun env ->
      let clock = Eio.Stdenv.clock env in
      witness clock (fun () -> Eio.Time.sleep clock 0.1);
      Eio.Switch.run (fun sw ->
          let config : Ox_blocking.Pool.config =
            {
              max_threads =
                (match Ox.Concurrency.of_int 1 with
                | Ok bound -> bound
                | Error _ -> failwith "invalid literal bound");
              max_queued = 1;
              shutdown_policy = Drain;
            }
          in
          let pool = Ox_blocking.Pool.create ~sw config in
          List.iter
            (fun wait ->
              witness clock (fun () ->
                  match Ox_blocking.run ~pool wait with
                  | Ok () -> ()
                  | Error _ -> failwith "pool shutdown"))
            [
              (fun () -> Unix.sleepf 0.1);
              (fun () -> Thread.delay 0.1);
              (fun () -> Unix.sleep 1);
            ];
          Ox_blocking.Pool.shutdown pool))
