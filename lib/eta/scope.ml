let classify ex bt = match ex with
  | Eio.Cancel.Cancelled reason -> Cause.Interrupt (Interrupt_id.of_exn reason)
  | _ -> Cause.Die (ex, bt)

let run f =
  let body = ref None in
  try
    let outcome = Eio.Switch.run (fun sw ->
      let result =
        try match f sw with
          | Ok value -> Exit.Success value
          | Error err -> Exit.Failure (Cause.Fail err)
        with ex -> Exit.Failure (classify ex (Printexc.get_raw_backtrace ()))
      in
      body := Some result; result) in
    outcome
  with ex ->
    let bt = Printexc.get_raw_backtrace () in
    let cleanup = classify ex bt in
    match !body with
    | Some (Exit.Failure primary) -> Exit.Failure (Cause.Suppressed {primary; finalizer=cleanup})
    | Some (Exit.Success _) -> Exit.Failure (Cause.Finalizer cleanup)
    | None -> Exit.Failure cleanup
