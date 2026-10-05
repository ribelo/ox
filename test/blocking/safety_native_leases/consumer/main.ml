(* ^safe-zgfv ^safe-sw86 ^safe-bt9f ^safe-tlyw: installed public API only.
   Actual native descriptor/buffer ownership, not production NemaOwner adoption.
   Aliases are allowed: this does not assert a Unique or must-close guarantee. *)
open Ox_blocking

exception Observer_defect

let require name condition = if not condition then failwith name
let inc n = ignore (Atomic.fetch_and_add n 1)

let () =
  Printexc.record_backtrace true;
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let p =
            Pool.create ~sw
              { max_threads = 1; max_queued = 1; shutdown_policy = Pool.Drain }
          in
          let fd, writer = Unix.pipe ~cloexec:true () in
          let buffer = Bytes.create 1 in
          let permit = Semaphore.Counting.make 0 in
          let started = Eio.Semaphore.make 0 in
          let settled = Eio.Semaphore.make 0 in
          let closed = Atomic.make 0 in
          let interrupted = Atomic.make 0 in
          let physical = Atomic.make false in
          let owner_thread = Thread.id (Thread.self ()) in
          let release = function
            | Unclaimed -> failwith "claimed native lease withdrawn"
            | Settled result ->
                Fun.protect
                  ~finally:(fun () ->
                    Unix.close fd;
                    inc closed;
                    Eio.Semaphore.release settled)
                  (fun () ->
                    require "physical completion before release" (Atomic.get physical);
                    require "owner Eio thread" (owner_thread = Thread.id (Thread.self ()));
                    Eio.Fiber.yield ();
                    require "native read outcome" (result = Ok (Ok 1));
                    raise Observer_defect)
          in
          let native () =
            Eio.Semaphore.release started;
            Semaphore.Counting.acquire permit;
            let count = Unix.read fd buffer 0 1 in
            Atomic.set physical true;
            Ok count
          in
          Fun.protect
            ~finally:(fun () ->
              Semaphore.Counting.release permit;
              Unix.close writer;
              if Atomic.get closed = 0 then Unix.close fd)
            (fun () ->
              Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                  let caller =
                    Eio.Fiber.fork_promise ~sw (fun () ->
                        Eio.Time.with_timeout env#clock 0.01 (fun () ->
                            match
                              run_leased_result ~pool:p ~release
                                ~on_cancel:(fun () -> inc interrupted)
                                native
                            with
                            | Ok count -> Ok count
                            | Error error ->
                                Error
                                  (error
                                    :> [ `Timeout
                                       | `Requires_drain
                                       | `Shutting_down
                                       | `Callback of _ ])))
                  in
                  Eio.Semaphore.acquire started;
                  require "caller timeout" (Eio.Promise.await_exn caller = Error `Timeout);
                  require "lease retained after timeout" (Atomic.get closed = 0);
                  require "interruption exactly once" (Atomic.get interrupted = 1);
                  (match try_run ~pool:p (fun () -> ()) with
                  | Not_run Saturated -> ()
                  | _ -> failwith "physical slot released early");
                  require "write to retained descriptor"
                    (Unix.write writer (Bytes.of_string "x") 0 1 = 1);
                  Semaphore.Counting.release permit;
                  Eio.Semaphore.acquire settled;
                  (match
                     run_leased_result ~pool:p ~release:(fun _ -> ()) (fun () -> Ok 17)
                   with
                  | Ok 17 -> ()
                  | _ -> failwith "new admission before Drain");
                  require "native close before any shutdown" (Atomic.get closed = 1);
                  require "buffer retained through native read" (Bytes.get buffer 0 = 'x');
                  for _ = 1 to 2 do
                    match Pool.shutdown p with
                    | () -> failwith "late observer defect missing from Drain"
                    | exception Observer_defect ->
                        require "original defect trace"
                          (Printexc.raw_backtrace_to_string
                             (Printexc.get_raw_backtrace ())
                          <> "")
                  done;
                  require "release terminal once" (Atomic.get closed = 1)));
          let detached =
            Pool.create ~sw
              { max_threads = 1; max_queued = 1; shutdown_policy = Pool.Detach_started }
          in
          let unclaimed = Atomic.make 0 in
          (match
             run_leased_result ~pool:detached
               ~release:(function
                 | Unclaimed -> inc unclaimed | Settled _ -> assert false)
               (fun () -> failwith "Detach callback executed")
           with
          | Error `Requires_drain -> ()
          | _ -> failwith "Detach not rejected");
          require "Detach Unclaimed once" (Atomic.get unclaimed = 1);
          Pool.shutdown detached));
  print_endline
    "installed public native lease API: physical retention, late defect capacity, Drain \
     and Detach passed"
