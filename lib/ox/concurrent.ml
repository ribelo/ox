(* Thin wrappers over Eio's own structured concurrency. No Ox-owned switch: each
   combinator runs in the caller's cancellation context and Eio cancels and awaits the
   losers. A typed [Error] leaves a fiber as the boundary's private exception (see
   [Scope.exit_on_error]) so that Eio's fail-fast machinery treats it like any exception;
   the boundary turns it back into the [Error] the body returned. Anything else the body
   raises propagates untouched. *)

let check ~sw = Eio.Switch.check sw
let ok_or_end ended f = match f () with Ok value -> value | Error e -> raise (ended e)

(* [Eio.Fiber.pair] documents fail-fast but forks its first side as a promise, so a
   failure there does not cancel the second side (found by the first run of this
   rewrite: a blocked sibling hung the pair). [Fiber.both] reports through the switch and
   does cancel, so [par] is [both] with the two results kept in cells. *)
(* ^nonce-nngp: erase affine modes only at the guarded Eio boundary. *)
let par ~sw (f @ once) (g @ once) =
  let f = Once.guard f and g = Once.guard g in
  check ~sw;
  let left = ref None and right = ref None in
  Scope.exit_on_error (fun ended ->
      Eio.Fiber.both
        (fun () -> left := Some (ok_or_end ended f))
        (fun () -> right := Some (ok_or_end ended g));
      (Option.get !left, Option.get !right))

let both ~sw (f @ once) (g @ once) =
  let f = Once.guard f and g = Once.guard g in
  check ~sw;
  Scope.exit_on_error (fun ended ->
      Eio.Fiber.both (fun () -> ok_or_end ended f) (fun () -> ok_or_end ended g))

(* Legacy List/Array helpers require many; consume the affine spine first. *)
let rec guard_branches (fs @ once) =
  match fs with [] -> [] | f :: rest -> Once.guard f :: guard_branches rest

let all ~sw (fs @ once) =
  let fs = guard_branches fs in
  check ~sw;
  let tasks = Array.of_list fs in
  let values = Array.make (Array.length tasks) None in
  Scope.exit_on_error (fun ended ->
      Eio.Fiber.all (List.mapi (fun i f () -> values.(i) <- Some (ok_or_end ended f)) fs);
      Array.to_list (Array.map Option.get values))

let for_each ~sw ~concurrency xs f =
  check ~sw;
  if concurrency < 1 then invalid_arg "Concurrent.for_each: concurrency must be positive";
  Scope.exit_on_error (fun ended ->
      Eio.Fiber.List.map ~max_fibers:concurrency
        (fun x -> ok_or_end ended (fun () -> f x))
        xs)

let race ~sw (fs @ once) =
  let fs = guard_branches fs in
  check ~sw;
  match fs with
  | [] -> Error (Cause.Concurrent [])
  | _ ->
      let n = List.length fs in
      let failures = Array.make n None in
      let remaining = ref n in
      Scope.exit_on_error (fun ended ->
          Eio.Fiber.any
            (List.mapi
               (fun i f () ->
                 match f () with
                 | Ok value -> value
                 | Error e ->
                     failures.(i) <- Some (Cause.Fail e);
                     decr remaining;
                     if !remaining > 0 then Eio.Fiber.await_cancel ()
                     else
                       raise
                         (ended
                            (match Array.to_list (Array.map Option.get failures) with
                            | [ cause ] -> cause
                            | causes -> Cause.Concurrent causes)))
               fs))

let race_first ~sw (fs @ once) =
  let fs = guard_branches fs in
  check ~sw;
  if fs = [] then invalid_arg "Concurrent.race_first: no branches";
  Eio.Fiber.any (List.map (fun f () -> f ()) fs)

let with_background ~sw (background @ once) (body @ once) =
  let background = Once.guard background and body = Once.guard body in
  Scope.supervised_error ~sw (fun scope ->
      Scope.fork_error_daemon scope background;
      (* A background that failed before yielding has already ended the scope. *)
      Eio.Switch.check (Scope.switch scope);
      body ())
