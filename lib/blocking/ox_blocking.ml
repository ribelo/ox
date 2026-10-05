module Pool = struct
  type shutdown_policy = Drain | Detach_started

  type config = {
    max_threads : Ox.Concurrency.t;
    max_queued : int;
    shutdown_policy : shutdown_policy;
  }

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
    if config.max_queued < 0 then invalid_arg "Ox_blocking.Pool.create: invalid limits";
    let drained, resolve_drained = Eio.Promise.create () in
    {
      sw;
      name;
      config;
      slots = Eio.Semaphore.make (Ox.Concurrency.to_int config.max_threads);
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

let execute pool ?name ?on_cancel ?on_settled ?on_unclaimed fn =
  let label = Option.value name ~default:pool.Pool.name in
  (* ^safe-sw86: the actual native claim arbitrates against withdrawal, not a flag
     around [fn]. 0 = pending; 1 = claimed; 2 = withdrawn/caller gone; 3 = done. *)
  let state = Atomic.make 0 in
  let drain_policy = pool.Pool.config.shutdown_policy = Pool.Drain in
  (* ^safe-bt9f: slot accounting is separate from the terminal notification. All
     releases run on the owning Eio domain; retaining a defect never retains a slot. *)
  let slot_released = ref false in
  let release_slot () =
    if not !slot_released then (
      slot_released := true;
      Pool.release_slot pool)
  in
  let gone = Atomic.make false in
  let hook_failure = Atomic.make None in
  let notify_unclaimed () = Option.iter (fun hook -> hook ()) on_unclaimed in
  let withdraw () =
    if Atomic.compare_and_set state 0 2 then (
      inc pool.cancelled_before_start;
      true)
    else false
  in
  (* nblock-l78q: failure is published before checking [gone]. In the same Eio
     domain the second observer releases the slot: worker for Gone, waiting caller
     for Hook_failed, cancellation handler for a published failure. *)
  let finish_hook hook settled =
    match hook () with
    | () ->
        release_slot ();
        settled
    | exception ex ->
        let bt = Printexc.get_raw_backtrace () in
        if not drain_policy then release_slot ()
        else (
          Atomic.set hook_failure (Some (ex, bt));
          if Atomic.get gone then (
            Pool.retain pool (ex, bt);
            release_slot ()));
        Hook_failed (ex, bt)
  in
  let settle outcome settled =
    finish_hook (fun () -> Option.iter (fun hook -> hook outcome) on_settled) settled
  in
  (* ^safe-sw86: a pre-claim cancellation keeps its original exception, even if
     the mandatory Unclaimed delivery raises. No worker can claim after withdrawal. *)
  let abandon ~cancelled () =
    if withdraw () then
      Fun.protect ~finally:release_slot (fun () ->
          match notify_unclaimed () with
          | () -> ()
          | exception ex ->
              let bt = Printexc.get_raw_backtrace () in
              if cancelled then Pool.retain pool (ex, bt)
              else Printexc.raise_with_backtrace ex bt)
  in
  let worker =
    match
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
              else if withdraw () then finish_hook notify_unclaimed (Raised (ex, bt))
              else (
                (* ^safe-sw86 ^safe-bt9f: state 2 may belong to the caller's
                   suspended Unclaimed delivery. Only that delivery's finalizer
                   may return its slot; the withdrawn worker owns no cleanup. *)
                if Atomic.get state <> 2 then release_slot ();
                Raised (ex, bt)))
    with
    | worker -> worker
    | exception ex ->
        let bt = Printexc.get_raw_backtrace () in
        (* Synchronous owner-switch rejection occurs before any worker exists. *)
        abandon
          ~cancelled:(match ex with Eio.Cancel.Cancelled _ -> true | _ -> false)
          ();
        Printexc.raise_with_backtrace ex bt
  in
  match Eio.Promise.await worker with
  | Ok (Value value) -> value
  | Ok (Raised (ex, bt)) -> Printexc.raise_with_backtrace ex bt
  | Ok (Hook_failed (ex, bt)) ->
      if drain_policy then release_slot ();
      Printexc.raise_with_backtrace ex bt
  | Error ex ->
      (* The owner switch refused the worker fiber, so no callback can start. *)
      let bt = Printexc.get_raw_backtrace () in
      abandon ~cancelled:(match ex with Eio.Cancel.Cancelled _ -> true | _ -> false) ();
      Printexc.raise_with_backtrace ex bt
  | exception (Eio.Cancel.Cancelled _ as ex) ->
      let bt = Printexc.get_raw_backtrace () in
      Atomic.set gone true;
      (match Atomic.get hook_failure with
      | Some failure ->
          Pool.retain pool failure;
          release_slot ()
      | None -> ());
      if Atomic.get state = 0 then abandon ~cancelled:true ();
      if Atomic.compare_and_set state 1 2 then Option.iter (fun hook -> hook ()) on_cancel;
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

type 'a lease_end = Unclaimed | Settled of ('a, exn) result

let run_leased_result ~pool ?name ?on_cancel ~release fn =
  (* ^safe-zgfv ^safe-sw86: terminal delivery is independent of both worker claim
     and slot accounting. The worker owns the closure through physical completion. *)
  let terminal_delivered = Atomic.make false in
  let terminal ending =
    if Atomic.compare_and_set terminal_delivered false true then
      Eio.Cancel.protect (fun () -> release ending)
  in
  let unclaimed () = terminal Unclaimed in
  if Pool.shutdown_policy pool = Pool.Detach_started then (
    unclaimed ();
    Error `Requires_drain)
  else
    match reserve pool with
    | Error `Shutting_down ->
        unclaimed ();
        Error `Shutting_down
    | Ok () ->
        lift
          (execute pool ?name ?on_cancel ~on_unclaimed:unclaimed
             ~on_settled:(fun outcome -> terminal (Settled outcome))
             fn)
    | exception ex ->
        let bt = Printexc.get_raw_backtrace () in
        (match unclaimed () with
        | () -> ()
        | exception release_ex -> (
            let release_bt = Printexc.get_raw_backtrace () in
            match ex with
            | Eio.Cancel.Cancelled _ -> Pool.retain pool (release_ex, release_bt)
            | _ -> Printexc.raise_with_backtrace release_ex release_bt));
        Printexc.raise_with_backtrace ex bt

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
