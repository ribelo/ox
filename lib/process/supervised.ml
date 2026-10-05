type 'e reason = [ `Spawn of 'e | `Schedule_exhausted of Child.exit ]

type 'e event =
  | Started of int
  | Exited of int * Child.exit
  | Gave_up of 'e reason Ox.Cause.t
  | Stopped

type 'e t = {
  mutable generation : int;
  mutable dropped : int;
  events : 'e event Eio.Stream.t;
  mutable stopped : bool;
  context : Eio.Cancel.t Eio.Promise.t;
  finished : unit Eio.Promise.or_exn;
}

let generation t = t.generation
let events t = t.events
let dropped t = t.dropped

let emit t value =
  if Eio.Stream.length t.events >= 32 then (
    ignore (Eio.Stream.take_nonblocking t.events);
    t.dropped <- t.dropped + 1);
  Eio.Stream.add t.events value

let stop t =
  Eio.Cancel.protect (fun () ->
      if not t.stopped then (
        t.stopped <- true;
        if not (Eio.Promise.is_resolved t.finished) then
          Eio.Cancel.cancel (Eio.Promise.await t.context) Exit);
      Eio.Promise.await_exn t.finished)

let start ~sw ~clock ~schedule ~spawn =
  let origin = Eio.Time.Mono.now clock in
  let now_ms () =
    Mtime.span origin (Eio.Time.Mono.now clock) |> Mtime.Span.to_uint64_ns |> fun ns ->
    Int64.to_int (Int64.unsigned_div ns 1_000_000L)
  in
  let context, context_u = Eio.Promise.create () in
  let finished, finished_u = Eio.Promise.create () in
  let t =
    {
      generation = 0;
      dropped = 0;
      events = Eio.Stream.create 32;
      stopped = false;
      context;
      finished;
    }
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      let run () =
        Eio.Cancel.sub (fun ctx ->
            Eio.Promise.resolve context_u ctx;
            let rec loop driver =
              if not t.stopped then
                let outcome =
                  Eio.Switch.run (fun child_sw ->
                      match spawn ~sw:child_sw with
                      | Error error -> Error error
                      | Ok child ->
                          t.generation <- t.generation + 1;
                          let n = t.generation in
                          emit t (Started n);
                          Ok (n, Child.await child))
                in
                match outcome with
                | Error e -> emit t (Gave_up (Ox.Cause.Fail (`Spawn e)))
                | Ok (n, exit) -> (
                    emit t (Exited (n, exit));
                    let decision, next =
                      Ox.Schedule.step ~now_ms:(now_ms ()) ~input:exit driver
                    in
                    match decision with
                    | Ox.Schedule.Done _ ->
                        emit t (Gave_up (Ox.Cause.Fail (`Schedule_exhausted exit)))
                    | Ox.Schedule.Continue metadata ->
                        Eio.Time.Mono.sleep clock
                          (Ox.Duration.to_seconds_float metadata.delay);
                        loop next)
            in
            loop (Ox.Schedule.start schedule))
      in
      let result =
        match run () with
        | () -> Ok ()
        | exception Eio.Cancel.Cancelled _ -> Ok ()
        | exception ex ->
            let bt = Printexc.get_raw_backtrace () in
            emit t (Gave_up (Ox.Cause.Die (ex, bt)));
            Error ex
      in
      Eio.Cancel.protect (fun () ->
          emit t Stopped;
          match result with
          | Ok () -> Eio.Promise.resolve_ok finished_u ()
          | Error ex -> Eio.Promise.resolve_error finished_u ex);
      `Stop_daemon);
  Eio.Switch.on_release sw (fun () -> stop t);
  t
