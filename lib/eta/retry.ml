let now_ms clock = int_of_float (Eio.Time.now clock *. 1000.)
let sleep clock delay = Eio.Time.sleep clock (Duration.to_seconds_float delay)

let rec retry_loop ~clock (f @ local) driver =
    match f () with
    | Ok _ as success -> success
    | Error error as failure -> (
        match Schedule.next ~now_ms:(now_ms clock) ~input:error driver with
        | None -> failure
        | Some (meta, next) ->
            sleep clock meta.delay;
            retry_loop ~clock f next)

let retry ~clock schedule (f @ local) =
  retry_loop ~clock f (Schedule.start schedule)

let rec repeat_loop ~clock (f @ local) driver =
    match f () with
    | Error _ as failure -> failure
    | Ok value -> (
        match Schedule.step ~now_ms:(now_ms clock) ~input:value driver with
        | Schedule.Done meta, _ -> Ok meta.output
        | Schedule.Continue meta, next ->
            sleep clock meta.delay;
            repeat_loop ~clock f next)

let repeat ~clock schedule (f @ local) =
  repeat_loop ~clock f (Schedule.start schedule)
