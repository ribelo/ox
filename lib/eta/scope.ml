let rec classify ex bt =
  match ex with
  (* [Switch.fail] accepts a cancellation exception; Eio wraps that reason again
     when waking sibling fibers. Preserve the original stop identity at any depth. *)
  | Eio.Cancel.Cancelled (Eio.Cancel.Cancelled _ as reason) -> classify reason bt
  | Eio.Cancel.Cancelled reason -> Cause.Interrupt (Interrupt_id.of_exn reason)
  | _ -> Cause.Die (ex, bt)

let rec only_exception wanted ex =
  ex == wanted
  ||
  match ex with
  | Eio.Exn.Multiple errors ->
      errors <> [] && List.for_all (fun (part, _) -> only_exception wanted part) errors
  | _ -> false

let rec only_cancellation reason = function
  | Eio.Cancel.Cancelled ex -> ex == reason
  | Eio.Exn.Multiple errors ->
      errors <> [] && List.for_all (fun (ex, _) -> only_cancellation reason ex) errors
  | _ -> false

let remove_matching matches (ex, bt) =
  if matches ex then None
  else
    match ex with
    | Eio.Exn.Multiple errors -> (
        let remaining = List.filter (fun (e, _) -> not (matches e)) errors in
        match remaining with
        | [] -> None
        | [ single ] -> Some single
        | many -> Some (Eio.Exn.Multiple many, bt))
    | _ -> Some (ex, bt)

let run f =
  let body = ref None in
  let child_error = ref None in
  try
    Eio.Switch.run (fun sw ->
        let result =
          try
            match f sw with
            | Ok value -> Exit.Success value
            | Error err -> Exit.Failure (Cause.Fail err)
          with ex -> Exit.Failure (classify ex (Printexc.get_raw_backtrace ()))
        in
        body := Some result;
        (* Registered after [f]: LIFO release order makes this run before user
         releases, once all child fibers have finished. *)
        Eio.Switch.on_release sw (fun () ->
            child_error :=
              match Eio.Switch.get_error sw with
              | Some (Eio.Cancel.Cancelled reason) -> Some reason
              | other -> other);
        result)
  with ex -> (
    let bt = Printexc.get_raw_backtrace () in
    match !body with
    | Some (Exit.Failure (Cause.Die (primary_ex, _) as primary))
      when only_exception primary_ex ex ->
        Exit.Failure primary
    | _ -> (
        match !child_error with
        | Some child_ex -> (
            let was_cancelled = only_cancellation child_ex ex in
            let child =
              if was_cancelled then Cause.Interrupt (Interrupt_id.of_exn child_ex)
              else classify child_ex bt
            in
            let primary =
              match !body with
              | Some (Exit.Failure (Cause.Interrupt _ as original)) when was_cancelled ->
                  original
              | Some (Exit.Failure (Cause.Interrupt _)) when only_exception child_ex ex ->
                  child
              | Some (Exit.Failure original) -> Cause.Concurrent [ original; child ]
              | _ -> child
            in
            let matching =
              if was_cancelled then only_cancellation child_ex
              else only_exception child_ex
            in
            match remove_matching matching (ex, bt) with
            | None -> Exit.Failure primary
            | Some (cleanup_ex, cleanup_bt) ->
                Exit.Failure
                  (Cause.Suppressed
                     { primary; finalizer = classify cleanup_ex cleanup_bt }))
        | None -> (
            let cleanup = classify ex bt in
            match !body with
            | Some (Exit.Failure primary) ->
                Exit.Failure (Cause.Suppressed { primary; finalizer = cleanup })
            | Some (Exit.Success _) -> Exit.Failure (Cause.Finalizer cleanup)
            | None -> Exit.Failure cleanup)))
