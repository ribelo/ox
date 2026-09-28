module Pool = struct
  type shutdown_policy = Drain | Detach_started
  type config = { max_threads : int; max_queued : int; shutdown_policy : shutdown_policy }

  type stats = {
    active : int;
    queued : int;
    waiting : int;
    completed : int;
    rejected : int;
    cancelled_before_start : int;
    detached : int;
  }

  type t = {
    sw : Eio.Switch.t;
    name : string;
    config : config;
    slots : Eio.Semaphore.t;
    queue : Eio.Semaphore.t;
    closed : bool Atomic.t;
    active : int Atomic.t;
    queued : int Atomic.t;
    waiting : int Atomic.t;
    completed : int Atomic.t;
    rejected : int Atomic.t;
    cancelled_before_start : int Atomic.t;
    detached : int Atomic.t;
  }

  let add t n = ignore (Atomic.fetch_and_add t n)

  let create ~sw ?(name = "blocking") config =
    if config.max_threads <= 0 || config.max_queued < 0 then
      invalid_arg "Eta_blocking.Pool.create: invalid limits";
    {
      sw;
      name;
      config;
      slots = Eio.Semaphore.make config.max_threads;
      queue = Eio.Semaphore.make config.max_queued;
      closed = Atomic.make false;
      active = Atomic.make 0;
      queued = Atomic.make 0;
      waiting = Atomic.make 0;
      completed = Atomic.make 0;
      rejected = Atomic.make 0;
      cancelled_before_start = Atomic.make 0;
      detached = Atomic.make 0;
    }

  let shutdown_policy t = t.config.shutdown_policy

  let stats t =
    {
      active = Atomic.get t.active;
      queued = Atomic.get t.queued;
      waiting = Atomic.get t.waiting;
      completed = Atomic.get t.completed;
      rejected = Atomic.get t.rejected;
      cancelled_before_start = Atomic.get t.cancelled_before_start;
      detached = Atomic.get t.detached;
    }

  let shutdown t =
    Atomic.set t.closed true;
    match t.config.shutdown_policy with
    | Detach_started -> Atomic.set t.detached (Atomic.get t.active)
    | Drain ->
        (* Reservations also hold slots. Each waiter checks [closed] before
           scheduling native work and releases its reservation. *)
        for _ = 1 to t.config.max_threads do
          Eio.Semaphore.acquire t.slots
        done;
        for _ = 1 to t.config.max_threads do
          Eio.Semaphore.release t.slots
        done
end

type admission_failure = Saturated | Shutting_down
type 'a try_run_outcome = Completed of 'a | Not_run of admission_failure

let inc x = ignore (Atomic.fetch_and_add x 1)
let dec x = ignore (Atomic.fetch_and_add x (-1))

let reserve pool =
  if Atomic.get pool.Pool.closed then Error `Shutting_down
  else (
    inc pool.waiting;
    Fun.protect
      ~finally:(fun () -> dec pool.waiting)
      (fun () ->
        if Eio.Semaphore.get_value pool.slots > 0 then Eio.Semaphore.acquire pool.slots
        else if pool.config.max_queued = 0 then Eio.Semaphore.acquire pool.slots
        else (
          Eio.Semaphore.acquire pool.queue;
          inc pool.queued;
          Fun.protect
            ~finally:(fun () ->
              dec pool.queued;
              Eio.Semaphore.release pool.queue)
            (fun () -> Eio.Semaphore.acquire pool.slots));
        if Atomic.get pool.closed then (
          Eio.Semaphore.release pool.slots;
          Error `Shutting_down)
        else Ok ()))

let try_reserve pool =
  if Atomic.get pool.Pool.closed then Error Shutting_down
  else if Eio.Semaphore.get_value pool.slots = 0 then (
    inc pool.rejected;
    Error Saturated)
  else (
    Eio.Semaphore.acquire pool.slots;
    if Atomic.get pool.closed then (
      Eio.Semaphore.release pool.slots;
      Error Shutting_down)
    else Ok ())

let execute pool ?name ?on_cancel ?on_settled fn =
  let label = Option.value name ~default:pool.Pool.name in
  (* 0 = pending; 1 = running; 2 = caller abandoned; 3 = physically done.
     Only the winner of 0 -> 1 starts work. If cancellation wins 0 -> 2,
     it releases the reservation; a late worker performs no callback. *)
  let state = Atomic.make 0 in
  (* nblk-2h3g: the worker fiber lives on the pool owner's switch, so [on_settled] runs in
     the owner's Eio context once the callback has physically finished (state 3), whether
     or not the caller is still waiting. A call abandoned before a worker claimed it never
     ran, so it never settles. *)
  (* The slot is released here, after [on_settled], not on the system thread: a [Drain]
     shutdown waits for every slot, so when it returns every lease has been released. *)
  let settle outcome =
    if Atomic.get state = 3 then
      Fun.protect
        ~finally:(fun () -> Eio.Semaphore.release pool.slots)
        (fun () -> Option.iter (fun hook -> hook outcome) on_settled)
  in
  let worker =
    Eio.Fiber.fork_promise ~sw:pool.Pool.sw (fun () ->
        match
          Eio_unix.run_in_systhread ~label (fun () ->
              if Atomic.compare_and_set state 0 1 then (
                inc pool.Pool.active;
                Fun.protect
                  ~finally:(fun () ->
                    dec pool.active;
                    inc pool.completed;
                    Atomic.set state 3)
                  fn)
              else (
                assert (Atomic.get state = 2);
                raise Exit))
        with
        | value ->
            settle (Ok value);
            Ok value
        | exception ex ->
            let bt = Printexc.get_raw_backtrace () in
            settle (Error ex);
            if Atomic.compare_and_set state 0 2 then (
              inc pool.cancelled_before_start;
              Eio.Semaphore.release pool.slots);
            Error (ex, bt))
  in
  try
    match Eio.Promise.await_exn worker with
    | Ok value -> Ok value
    | Error (ex, bt) -> Printexc.raise_with_backtrace ex bt
  with Eio.Cancel.Cancelled _ as ex ->
    if Atomic.compare_and_set state 0 2 then (
      inc pool.cancelled_before_start;
      Eio.Semaphore.release pool.slots)
    else if Atomic.compare_and_set state 1 2 then
      Option.iter (fun hook -> hook ()) on_cancel;
    raise ex

let run ~pool ?name ?on_cancel ?on_settled fn =
  match reserve pool with
  | Error _ as e -> e
  | Ok () -> execute pool ?name ?on_cancel ?on_settled fn

let try_run ~pool ?name ?on_cancel ?on_settled fn =
  match try_reserve pool with
  | Error e -> Not_run e
  | Ok () -> (
      match execute pool ?name ?on_cancel ?on_settled fn with
      | Ok v -> Completed v
      | Error _ -> assert false)

let lift = function Ok x -> Ok x | Error e -> Error (`Callback e)

let run_result ~pool ?name ?on_cancel ?on_settled fn =
  match run ~pool ?name ?on_cancel ?on_settled fn with
  | Ok result -> lift result
  | Error `Shutting_down -> Error `Shutting_down

let try_run_result ~pool ?name ?on_cancel ?on_settled fn =
  match try_run ~pool ?name ?on_cancel ?on_settled fn with
  | Not_run e -> Ok (Not_run e)
  | Completed result -> Result.map (fun x -> Completed x) (lift result)

let run_result_timeout ~pool ~clock ~timeout ~on_timeout ?name ?on_cancel ?on_settled fn =
  match
    Eio.Time.with_timeout clock (Eta.Duration.to_seconds_float timeout) (fun () ->
        run_result ~pool ?name ?on_cancel ?on_settled fn)
  with
  | Error `Timeout -> Error (`Timed_out on_timeout)
  | (Ok _ | Error (`Callback _ | `Shutting_down)) as result -> result

let try_run_result_timeout ~pool ~clock ~timeout ~on_timeout ?name ?on_cancel ?on_settled
    fn =
  match
    Eio.Time.with_timeout clock (Eta.Duration.to_seconds_float timeout) (fun () ->
        try_run_result ~pool ?name ?on_cancel ?on_settled fn)
  with
  | Error `Timeout -> Error (`Timed_out on_timeout)
  | (Ok _ | Error (`Callback _)) as result -> result
