(* ^safe-p9cw ^safe-8peq: schedule milliseconds are local monotonic elapsed
   time. Divide integer nanoseconds before converting; never round an epoch. *)
let now_ms clock origin =
  Mtime.span origin (Eio.Time.Mono.now clock)
  |> Mtime.Span.to_uint64_ns
  |> fun ns -> Int64.to_int (Int64.unsigned_div ns 1_000_000L)

let sleep clock delay = Eio.Time.Mono.sleep clock (Duration.to_seconds_float delay)

type ('a, 'e) policy = {
  is_success : 'a -> bool;
  is_worth_retrying : 'e -> bool;
  on_retry : int -> ('a, 'e) result -> unit;
}

let default_policy =
  { is_success = (fun _ -> true); is_worth_retrying = (fun _ -> true); on_retry = (fun _ _ -> ()) }

let rec retry_loop ~clock ~origin ~policy (f @ local) driver attempt =
  let result = f () in
  let settled =
    match result with
    | Ok value -> policy.is_success value
    | Error e -> not (policy.is_worth_retrying e)
  in
  if settled then result
  else
    match Schedule.next ~now_ms:(now_ms clock origin) ~input:result driver with
    | None -> result
    | Some (meta, next) ->
        policy.on_retry attempt result;
        sleep clock meta.delay;
        retry_loop ~clock ~origin ~policy f next (attempt + 1)

let retry ~clock ?(policy = default_policy) schedule (f @ local) =
  let origin = Eio.Time.Mono.now clock in
  retry_loop ~clock ~origin ~policy f (Schedule.start schedule) 1

let rec repeat_loop ~clock ~origin (f @ local) driver =
    match f () with
    | Error _ as failure -> failure
    | Ok value -> (
        match Schedule.step ~now_ms:(now_ms clock origin) ~input:value driver with
        | Schedule.Done meta, _ -> Ok meta.output
        | Schedule.Continue meta, next ->
            sleep clock meta.delay;
            repeat_loop ~clock ~origin f next)

let repeat ~clock schedule (f @ local) =
  let origin = Eio.Time.Mono.now clock in
  repeat_loop ~clock ~origin f (Schedule.start schedule)
