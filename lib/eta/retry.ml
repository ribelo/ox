let now_ms clock = int_of_float (Eio.Time.now clock *. 1000.)
let sleep clock delay = Eio.Time.sleep clock (Duration.to_seconds_float delay)

let retry ~clock schedule f =
  let rec loop driver = match f () with
    | Ok _ as success -> success
    | Error error as failure ->
        (match Schedule.next ~now_ms:(now_ms clock) ~input:error driver with
         | None -> failure
         | Some (meta, next) -> sleep clock meta.delay; loop next)
  in loop (Schedule.start schedule)

let repeat ~clock schedule f =
  let rec loop driver = match f () with
    | Error _ as failure -> failure
    | Ok value ->
        (match Schedule.step ~now_ms:(now_ms clock) ~input:value driver with
         | Schedule.Done meta, _ -> Ok meta.output
         | Schedule.Continue meta, next -> sleep clock meta.delay; loop next)
  in loop (Schedule.start schedule)
