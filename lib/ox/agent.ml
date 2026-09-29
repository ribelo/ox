(* One owner fiber, a bounded {!Channel} of closures, and one promise per request that
   needs an answer. A request is a closure over the typed promise, so replies of different
   types share one mailbox without a message type or a witness. *)

type 'state request = {
  run : 'state -> 'state * (unit -> unit);
      (* the next state and the acknowledgement to run once it is committed *)
  abandon : unit -> unit; (* settle the reply with [`Agent_stopped] *)
}

type 'state t = { mailbox : ('state request, unit) Channel.t }

let stop t in_flight =
  Channel.done_ t.mailbox;
  Option.iter (fun request -> request.abandon ()) !in_flight;
  in_flight := None;
  let rec drain () =
    match Channel.try_receive t.mailbox with
    | Ok request ->
        request.abandon ();
        drain ()
    | Error _ -> ()
  in
  drain ()

let create ?(capacity = 1024) ~sw ~init () =
  if capacity < 1 then invalid_arg "Ox.Agent.create: capacity must be at least 1";
  Eio.Switch.check sw;
  let t = { mailbox = Channel.create ~capacity () } in
  let in_flight = ref None in
  let rec loop state =
    Eio.Fiber.check ();
    match Channel.receive t.mailbox with
    | Error _ -> ()
    | Ok request ->
        in_flight := Some request;
        let state, acknowledge = Eio.Cancel.protect (fun () -> request.run state) in
        in_flight := None;
        acknowledge ();
        loop state
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      match loop (Eio.Cancel.protect init) with
      | exception ex ->
          let bt = Printexc.get_raw_backtrace () in
          stop t in_flight;
          Printexc.raise_with_backtrace ex bt
      | () ->
          stop t in_flight;
          `Stop_daemon);
  t

(* Enqueue a request and wait for its answer. [run settle] builds the closure the owner
   runs; [settle] resolves this request's promise, at most once. *)
let request t run =
  let promise, resolver = Eio.Promise.create () in
  let settled = ref false in
  let settle answer =
    if not !settled then (
      settled := true;
      Eio.Promise.resolve resolver answer)
  in
  let request =
    { run = run settle; abandon = (fun () -> settle (Error `Agent_stopped)) }
  in
  match Channel.send t.mailbox request with
  | Error _ -> Error `Agent_stopped
  | Ok () -> Eio.Promise.await promise

let get t ~fn =
  request t (fun settle state ->
      let reply = fn state in
      (state, fun () -> settle (Ok reply)))

let update t ~fn =
  request t (fun settle state ->
      let next = fn state in
      (next, fun () -> settle (Ok ())))

let get_and_update t ~fn =
  request t (fun settle state ->
      let reply, next = fn state in
      (next, fun () -> settle (Ok reply)))

let cast t ~fn =
  match
    Channel.send t.mailbox { run = (fun state -> (fn state, ignore)); abandon = ignore }
  with
  | Ok () -> Ok ()
  | Error _ -> Error `Agent_stopped

let update_result t ~fn =
  request t (fun settle state ->
      match fn state with
      | Ok next -> (next, fun () -> settle (Ok ()))
      | Error e -> (state, fun () -> settle (Error e)))

let get_and_update_result t ~fn =
  request t (fun settle state ->
      match fn state with
      | Ok (reply, next) -> (next, fun () -> settle (Ok reply))
      | Error e -> (state, fun () -> settle (Error e)))
