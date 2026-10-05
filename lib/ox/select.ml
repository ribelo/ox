type 'r ready = { poll : unit -> 'r option; wait : unit -> unit }

type 'r timeout = {
  deadline : unit -> Mtime.t option;
  wait_deadline : Mtime.t option -> unit;
  fire : unit -> 'r;
}

type 'r clause = Ready of 'r ready | Default of (unit -> 'r) | Timeout of 'r timeout

let receive_clause channel handler =
  Ready
    {
      poll =
        (fun () ->
          match Channel.try_receive channel with
          | Ok v -> Some (handler (Ok v))
          | Error `Empty -> None
          | Error ((`Done | `Error _) as closed) -> Some (handler (Error closed)));
      wait = (fun () -> Channel.wait_changed channel);
    }

let send_clause channel value handler =
  Ready
    {
      poll =
        (fun () ->
          match Channel.try_send channel value with
          | Ok () -> Some (handler (Ok ()))
          | Error `Full -> None
          | Error ((`Done | `Error _) as closed) -> Some (handler (Error closed)));
      wait = (fun () -> Channel.wait_changed channel);
    }

let default_clause f = Default f

let timeout_clause ~clock duration fire =
  Timeout
    {
      (* ^safe-p9cw ^safe-5a9k: pin one native deadline when select begins.
         Keep the timer outside handlers: a committed clause may suspend without
         its handler being cancelled by the losing timeout. *)
      deadline =
        (fun () ->
          let ms = Int64.of_int (Duration.to_ms duration) in
          if ms > Int64.unsigned_div Int64.minus_one 1_000_000L then None
          else
            Mtime.add_span (Eio.Time.Mono.now clock)
              (Mtime.Span.of_uint64_ns (Int64.mul ms 1_000_000L)));
      wait_deadline =
        (function
        | Some at -> Eio.Time.Mono.sleep_until clock at
        | None -> Eio.Fiber.await_cancel ());
      fire;
    }

(* One process-wide rotation point: each select starts one clause further along. *)
let cursor = Atomic.make 0

let select clauses =
  let ready = List.filter_map (function Ready r -> Some r | _ -> None) clauses in
  let defaults = List.filter_map (function Default f -> Some f | _ -> None) clauses in
  let timeouts = List.filter_map (function Timeout t -> Some t | _ -> None) clauses in
  if List.is_empty clauses then invalid_arg "Select.select: no clauses";
  if List.compare_length_with defaults 1 > 0 then
    invalid_arg "Select.select: more than one default clause";
  if List.compare_length_with timeouts 1 > 0 then
    invalid_arg "Select.select: more than one timeout clause";
  let ready = Array.of_list ready in
  let count = Array.length ready in
  let first =
    if count = 0 then 0 else Atomic.fetch_and_add cursor 1 land max_int mod count
  in
  let scan () =
    let rec go i =
      if i = count then None
      else
        match ready.((first + i) mod count).poll () with
        | Some _ as fired -> fired
        | None -> go (i + 1)
    in
    go 0
  in
  match scan () with
  | Some result -> result
  | None -> (
      match (defaults, timeouts) with
      | default :: _, _ -> default ()
      | [], [] ->
          let rec block () =
            Eio.Fiber.any (Array.to_list (Array.map (fun r -> r.wait) ready));
            match scan () with Some result -> result | None -> block ()
          in
          block ()
      | [], timeout :: _ ->
          let deadline = timeout.deadline () in
          let waits =
            (fun () ->
              timeout.wait_deadline deadline;
              true)
            :: Array.to_list
                 (Array.map
                    (fun r () ->
                      r.wait ();
                      false)
                    ready)
          in
          let rec block () =
            let expired = Eio.Fiber.any waits in
            match scan () with
            | Some result -> result
            | None -> if expired then timeout.fire () else block ()
          in
          block ())

let receive channels =
  if List.is_empty channels then invalid_arg "Select.receive: no channels";
  select (List.map (fun channel -> receive_clause channel Fun.id) channels)
