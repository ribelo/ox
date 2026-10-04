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
    held : int Atomic.t;
    drained : unit Eio.Promise.t;
    resolve_drained : unit Eio.Promise.u;
    retained : (exn * Printexc.raw_backtrace) option Atomic.t;
    active : int Atomic.t;
    queued : int Atomic.t;
    waiting : int Atomic.t;
    completed : int Atomic.t;
    rejected : int Atomic.t;
    cancelled_before_start : int Atomic.t;
    detached : int Atomic.t;
  }
  (* nblock-5siy nblock-8z91: [held] counts slot permits owned by an admitted call, from
     admission until its callback physically returned and [on_settled] ran (or until the
     call was abandoned before a worker claimed it). The pool, not any [shutdown] caller,
     owns the ending: [drained] is resolved once, by whichever fiber observes
     [closed && held = 0] -- the sealing [shutdown] or the last slot release. Drain
     callers only await it, so concurrent, repeated and cancelled callers never own
     permits. Admission increments [held] before re-checking [closed] and a release
     decrements it before reading [closed]; with sequentially consistent atomics at least
     one side sees the other, so no callback starts after the ending and no ending is
     missed. *)

  let add t n = ignore (Atomic.fetch_and_add t n)

  let create ~sw ?(name = "blocking") config =
    if config.max_threads <= 0 || config.max_queued < 0 then
      invalid_arg "Ox_blocking.Pool.create: invalid limits";
    let drained, resolve_drained = Eio.Promise.create () in
    {
      sw;
      name;
      config;
      slots = Eio.Semaphore.make config.max_threads;
      queue = Eio.Semaphore.make config.max_queued;
      closed = Atomic.make false;
      held = Atomic.make 0;
      drained;
      resolve_drained;
      retained = Atomic.make None;
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

  let finish_if_drained t =
    if Atomic.get t.closed && Atomic.get t.held = 0 then
      ignore (Eio.Promise.try_resolve t.resolve_drained ())

  (* An admitted call took a slot permit; it now belongs to the pool's ending. *)
  let hold t = add t.held 1

  let release_slot t =
    Eio.Semaphore.release t.slots;
    add t.held (-1);
    finish_if_drained t

  (* nblock-l78q: first settled-hook defect whose caller is gone; kept for the pool's
     lifetime and raised by every Drain. *)
  let retain t failure = ignore (Atomic.compare_and_set t.retained None (Some failure))

  let shutdown t =
    match t.config.shutdown_policy with
    | Detach_started ->
        Atomic.set t.closed true;
        Atomic.set t.detached (Atomic.get t.active)
    | Drain -> (
        (* nblock-l36w: the first call seals admission; later calls only join. *)
        if Atomic.compare_and_set t.closed false true then finish_if_drained t;
        (* nblock-8z91: cancelling this wait abandons only the wait. *)
        Eio.Promise.await t.drained;
        match Atomic.get t.retained with
        | None -> ()
        | Some (ex, bt) -> Printexc.raise_with_backtrace ex bt)
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
        Pool.hold pool;
        if Atomic.get pool.closed then (
          Pool.release_slot pool;
          Error `Shutting_down)
        else Ok ()))

let try_reserve pool =
  if Atomic.get pool.Pool.closed then Error Shutting_down
  else if Eio.Semaphore.get_value pool.slots = 0 then (
    inc pool.rejected;
    Error Saturated)
  else (
    Eio.Semaphore.acquire pool.slots;
    Pool.hold pool;
    if Atomic.get pool.closed then (
      Pool.release_slot pool;
      Error Shutting_down)
    else Ok ())

type 'a settled =
  | Value of 'a
  | Raised of exn * Printexc.raw_backtrace
  | Hook_failed of exn * Printexc.raw_backtrace

let execute pool ?name ?on_cancel ?on_settled fn =
  let label = Option.value name ~default:pool.Pool.name in
  (* 0 = pending; 1 = running; 2 = caller abandoned; 3 = physically done.
     Only the winner of 0 -> 1 starts work. If cancellation wins 0 -> 2,
     it releases the reservation; a late worker performs no callback. *)
  let state = Atomic.make 0 in
  let drain_policy = pool.Pool.config.shutdown_policy = Pool.Drain in
  (* nblock-l78q: in a Drain pool a failed [on_settled] hands its slot and defect to
     whichever of the worker and the caller comes second: the worker if the caller is
     already [gone], otherwise the caller, which either observes the defect or, being
     cancelled, retains it in the pool. Both run in the owner's domain without suspending
     between their write and read, so exactly one releases the slot and the slot is
     released only after the defect was observed or retained. *)
  let gone = Atomic.make false in
  let hook_failure = Atomic.make None in
  let release_cancelled_before_start () =
    if Atomic.compare_and_set state 0 2 then (
      inc pool.cancelled_before_start;
      Pool.release_slot pool)
  in
  (* nblk-2h3g: the worker fiber lives on the pool owner's switch, so [on_settled] runs in
     the owner's Eio context once the callback has physically finished (state 3), whether
     or not the caller is still waiting. A call abandoned before a worker claimed it never
     ran, so it never settles. *)
  (* nblock-faq7: the slot is released here, after [on_settled], not on the system thread:
     a [Drain] shutdown waits until no slot is held, so when it returns every hook ran. *)
  let settle outcome settled =
    match Option.iter (fun hook -> hook outcome) on_settled with
    | () ->
        Pool.release_slot pool;
        settled
    | exception ex ->
        let bt = Printexc.get_raw_backtrace () in
        if not drain_policy then Pool.release_slot pool
        else (
          Atomic.set hook_failure (Some (ex, bt));
          if Atomic.get gone then (
            Pool.retain pool (ex, bt);
            Pool.release_slot pool));
        Hook_failed (ex, bt)
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
        | value -> settle (Ok value) (Value value)
        | exception ex ->
            let bt = Printexc.get_raw_backtrace () in
            if Atomic.get state = 3 then settle (Error ex) (Raised (ex, bt))
            else (
              release_cancelled_before_start ();
              Raised (ex, bt)))
  in
  match Eio.Promise.await worker with
  | Ok (Value value) -> value
  | Ok (Raised (ex, bt)) -> Printexc.raise_with_backtrace ex bt
  | Ok (Hook_failed (ex, bt)) ->
      if drain_policy then Pool.release_slot pool;
      Printexc.raise_with_backtrace ex bt
  | Error ex ->
      (* The owner switch refused the worker fiber, so no callback can start. *)
      release_cancelled_before_start ();
      raise ex
  | exception (Eio.Cancel.Cancelled _ as ex) ->
      let bt = Printexc.get_raw_backtrace () in
      Atomic.set gone true;
      (match Atomic.get hook_failure with
      | Some failure ->
          Pool.retain pool failure;
          Pool.release_slot pool
      | None -> ());
      if Atomic.compare_and_set state 0 2 then (
        inc pool.cancelled_before_start;
        Pool.release_slot pool)
      else if Atomic.compare_and_set state 1 2 then
        Option.iter (fun hook -> hook ()) on_cancel;
      Printexc.raise_with_backtrace ex bt

let run ~pool ?name ?on_cancel ?on_settled fn =
  match reserve pool with
  | Error _ as e -> e
  | Ok () -> Ok (execute pool ?name ?on_cancel ?on_settled fn)

let try_run ~pool ?name ?on_cancel ?on_settled fn =
  match try_reserve pool with
  | Error e -> Not_run e
  | Ok () -> Completed (execute pool ?name ?on_cancel ?on_settled fn)

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
    Eio.Time.with_timeout clock (Ox.Duration.to_seconds_float timeout) (fun () ->
        run_result ~pool ?name ?on_cancel ?on_settled fn)
  with
  | Error `Timeout -> Error (`Timed_out on_timeout)
  | (Ok _ | Error (`Callback _ | `Shutting_down)) as result -> result

let try_run_result_timeout ~pool ~clock ~timeout ~on_timeout ?name ?on_cancel ?on_settled
    fn =
  match
    Eio.Time.with_timeout clock (Ox.Duration.to_seconds_float timeout) (fun () ->
        try_run_result ~pool ?name ?on_cancel ?on_settled fn)
  with
  | Error `Timeout -> Error (`Timed_out on_timeout)
  | (Ok _ | Error (`Callback _)) as result -> result
