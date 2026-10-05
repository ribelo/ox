(* The private exception that carries a typed error out of a supervised boundary. Its
   payload is only an identity: the error itself waits in the boundary's own cell, so the
   exception is monomorphic and never escapes an interface. *)
exception Ended of int

let next_boundary = Atomic.make 0

let rec classify ex bt =
  match ex with
  (* A boundary's own exception that reached a classifier has left its scope: that is a
     broken invariant, not a typed failure of any type we could name. *)
  | Ended _ -> Cause.Die (Failure "Ox.Scope: a supervised error escaped its scope", bt)
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

let rec remove_ended id (ex, bt) =
  match ex with
  | Ended seen when seen = id -> None
  | Eio.Exn.Multiple errors -> (
      match List.filter_map (remove_ended id) errors with
      | [] -> None
      | [ single ] -> Some single
      | many -> Some (Eio.Exn.Multiple many, bt))
  | _ -> Some (ex, bt)

let exit_on_error (type e a) (f : (e -> exn) -> a) : (a, e) result =
  let id = Atomic.fetch_and_add next_boundary 1 in
  let error : e option ref = ref None in
  let ended e =
    (match !error with None -> error := Some e | Some _ -> ());
    Ended id
  in
  match f ended with
  | value -> Ok value
  | exception ex -> (
      let bt = Printexc.get_raw_backtrace () in
      match !error with
      | None -> Printexc.raise_with_backtrace ex bt
      | Some e -> (
          match remove_ended id (ex, bt) with
          | Some (rest, rest_bt) -> Printexc.raise_with_backtrace rest rest_bt
          | None ->
              (* Only our own exception: the error is the outcome, unless the caller
                 was cancelled meanwhile, which stays a cancellation. *)
              Eio.Fiber.check ();
              Error e))

type 'e t = { sw : Eio.Switch.t; ended : 'e -> exn }
type ('a, 'e) fork = ('a, 'e) result Eio.Promise.t

let switch t = t.sw

let supervised_error ~sw f =
  Eio.Switch.check sw;
  exit_on_error (fun ended ->
      Eio.Switch.run ~name:"supervised_error" (fun child ->
          match f { sw = child; ended } with
          | Ok value -> value
          | Error e -> raise (ended e)))

(* ^nonce-r7mi: retained Eio callbacks cross the guarded boundary. *)
let fork_error t (f @ once) =
  let f = Once.guard f in
  let promise, resolve = Eio.Promise.create () in
  Eio.Fiber.fork ~sw:t.sw (fun () ->
      let result = f () in
      Eio.Promise.resolve resolve result;
      match result with Ok _ -> () | Error e -> raise (t.ended e));
  promise

let fork t (f @ once) = Eio.Fiber.fork ~sw:t.sw (Once.guard f)

let fork_daemon t (f @ once) =
  let f = Once.guard f in
  Eio.Fiber.fork_daemon ~sw:t.sw (fun () ->
      f ();
      `Stop_daemon)

let fork_error_daemon t (f @ once) =
  let f = Once.guard f in
  Eio.Fiber.fork_daemon ~sw:t.sw (fun () ->
      match f () with Ok () -> `Stop_daemon | Error e -> raise (t.ended e))

(* ^nonce-4jzx: Eio retains releases beyond this call. *)
let on_release t (release @ once) = Eio.Switch.on_release t.sw (Once.guard release)

let await = Eio.Promise.await
