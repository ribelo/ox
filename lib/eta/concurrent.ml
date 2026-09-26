type 'a outcome = Value of 'a | Raised of exn * Printexc.raw_backtrace

let capture f = try Value (f ()) with ex -> Raised (ex, Printexc.get_raw_backtrace ())

let unwrap = function
  | Value v -> v
  | Raised (ex, bt) -> Printexc.raise_with_backtrace ex bt

let stopped id = function
  | Eio.Cancel.Cancelled reason -> (
      match Interrupt_id.of_exn reason with
      | Some seen -> Interrupt_id.equal id seen
      | None -> false)
  | _ -> false

let child_run ~sw fn =
  Eio.Switch.check sw;
  Eio.Promise.await_exn (Eio.Fiber.fork_promise ~sw (fun () -> Eio.Switch.run fn))

let stop_other id contexts except =
  Array.iteri
    (fun i ctx ->
      if i <> except then
        Option.iter
          (fun c ->
            (* A branch may have completed before a later branch wins. Eio rejects
               cancellation of a finished context, even though it was published. *)
            match Eio.Cancel.get_error c with
            | Some (Invalid_argument _) -> ()
            | _ -> Eio.Cancel.cancel c (Interrupt_id.stop id))
          !ctx)
    contexts

let race ~sw fs =
  Eio.Switch.check sw;
  let tasks = Array.of_list fs in
  let n = Array.length tasks in
  if n = 0 then Error (Cause.Concurrent [])
  else
    child_run ~sw (fun child ->
        let result, resolve = Eio.Promise.create () in
        let contexts = Array.init n (fun _ -> ref None) in
        let failures = Array.make n None in
        let remaining = ref n in
        let settled = ref false in
        let stop_id = Interrupt_id.create () in
        let all_failed () =
          settled := true;
          let causes = Array.to_list (Array.map Option.get failures) in
          Eio.Promise.resolve resolve
            (Error
               (match causes with
               | [ cause ] -> cause
               | causes -> Cause.Concurrent causes))
        in
        Array.iteri
          (fun i f ->
            if not !settled then
              Eio.Fiber.fork ~sw:child (fun () ->
                  Eio.Cancel.sub (fun ctx ->
                      contexts.(i) := Some ctx;
                      let outcome = capture f in
                      match outcome with
                      | Value (Ok value) when not !settled ->
                          settled := true;
                          Eio.Promise.resolve resolve (Ok value);
                          stop_other stop_id contexts i
                      | Value (Error error) when not !settled ->
                          failures.(i) <- Some (Cause.Fail error);
                          decr remaining;
                          if !remaining = 0 then all_failed ()
                      | Raised (ex, _) when !settled && stopped stop_id ex -> ()
                      | Raised (ex, bt) when not !settled ->
                          failures.(i) <- Some (Scope.classify ex bt);
                          decr remaining;
                          if !remaining = 0 then all_failed ()
                      | Raised (ex, bt) -> Printexc.raise_with_backtrace ex bt
                      | Value _ -> ())))
          tasks;
        Eio.Promise.await result)

let all ~sw fs =
  Eio.Switch.check sw;
  let tasks = Array.of_list fs in
  let n = Array.length tasks in
  child_run ~sw (fun child ->
      let completed, resolve = Eio.Promise.create () in
      let contexts = Array.init n (fun _ -> ref None) in
      let values = Array.make n None in
      let remaining = ref n in
      let first_failure = ref None in
      let stop_id = Interrupt_id.create () in
      let resolved = ref false in
      let resolve_if_done () =
        if !remaining = 0 && not !resolved then (
          resolved := true;
          Eio.Promise.resolve resolve
            (match !first_failure with
            | Some outcome -> outcome
            | None -> Value (Ok (Array.to_list (Array.map Option.get values)))))
      in
      resolve_if_done ();
      Array.iteri
        (fun i f ->
          if !first_failure <> None then (
            decr remaining;
            resolve_if_done ())
          else
            Eio.Fiber.fork ~sw:child (fun () ->
                Eio.Cancel.sub (fun ctx ->
                    contexts.(i) := Some ctx;
                    let outcome = capture f in
                    (match outcome with
                    | Value (Ok value) -> values.(i) <- Some value
                    | Value (Error error) when !first_failure = None ->
                        first_failure := Some (Value (Error error));
                        stop_other stop_id contexts i
                    | Raised (ex, _) when !first_failure <> None && stopped stop_id ex ->
                        ()
                    | Raised (ex, bt) when !first_failure = None ->
                        first_failure := Some (Raised (ex, bt));
                        stop_other stop_id contexts i
                    | Raised (ex, bt) -> Printexc.raise_with_backtrace ex bt
                    | Value _ -> ());
                    decr remaining;
                    resolve_if_done ())))
        tasks;
      unwrap (Eio.Promise.await completed))

type ('a, 'b) side = Left of 'a | Right of 'b

let par ~sw f g =
  match
    all ~sw
      [
        (fun () -> Stdlib.Result.map (fun x -> Left x) (f ()));
        (fun () -> Stdlib.Result.map (fun x -> Right x) (g ()));
      ]
  with
  | Ok [ Left a; Right b ] -> Ok (a, b)
  | Error e -> Error e
  | Ok _ -> assert false

let with_background ~sw bg body =
  Eio.Switch.check sw;
  child_run ~sw (fun child ->
      let published, resolve = Eio.Promise.create () in
      let contexts = Array.init 2 (fun _ -> ref None) in
      let settled = ref false in
      let stop_id = Interrupt_id.create () in
      let publish i outcome =
        if not !settled then (
          settled := true;
          Eio.Promise.resolve resolve outcome;
          stop_other stop_id contexts i)
      in
      Eio.Fiber.fork ~sw:child (fun () ->
          Eio.Cancel.sub (fun ctx ->
              contexts.(0) := Some ctx;
              match capture bg with
              | Value (Ok ()) -> ()
              | Value (Error e) -> publish 0 (Value (Error e))
              | Raised (ex, _) when !settled && stopped stop_id ex -> ()
              | Raised (ex, bt) when !settled -> Printexc.raise_with_backtrace ex bt
              | Raised (ex, bt) -> publish 0 (Raised (ex, bt))));
      if not !settled then
        Eio.Fiber.fork ~sw:child (fun () ->
            Eio.Cancel.sub (fun ctx ->
                contexts.(1) := Some ctx;
                match capture body with
                | Value result -> publish 1 (Value result)
                | Raised (ex, _) when !settled && stopped stop_id ex -> ()
                | Raised (ex, bt) when !settled -> Printexc.raise_with_backtrace ex bt
                | Raised (ex, bt) -> publish 1 (Raised (ex, bt))));
      unwrap (Eio.Promise.await published))
