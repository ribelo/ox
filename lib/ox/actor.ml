(* One fiber owns the state; a bounded {!Channel} is the mailbox. Everything the fiber and
   its callers do to the shared fields runs without suspending (Eio schedules
   cooperatively), so the flags below need no lock. *)

type 'reply cell = { resolver : 'reply Eio.Promise.u; mutable settled : bool }
(* The write end of one ask, settled at most once: by the handler's answer or, if the
   actor stops first, by [`Actor_stopped]. *)

let answer cell value =
  if not cell.settled then (
    cell.settled <- true;
    Eio.Promise.resolve cell.resolver value)

type ('msg, 'result) envelope = { msg : 'msg; reply : 'result cell option }
type 'state item = State of 'state | End

module Changes = struct
  type 'state t = {
    buffer : 'state item Eio.Stream.t;
    capacity : int;
    mutable dropped : int;
    mutable ended : bool; (* [End] was pushed: no more items will be *)
    mutable finished : bool; (* [End] was taken: [next] answers [None] from now on *)
    mutable detach : unit -> unit;
  }

  (* The buffer has one slot beyond [capacity], so [End] always fits. *)
  let create capacity =
    {
      buffer = Eio.Stream.create (capacity + 1);
      capacity;
      dropped = 0;
      ended = false;
      finished = false;
      detach = ignore;
    }

  let push t state =
    if not t.ended then (
      if Eio.Stream.length t.buffer >= t.capacity then (
        ignore (Eio.Stream.take_nonblocking t.buffer);
        t.dropped <- t.dropped + 1);
      Eio.Stream.add t.buffer (State state))

  let finish t =
    if not t.ended then (
      t.ended <- true;
      Eio.Stream.add t.buffer End)

  let next t =
    if t.finished then None
    else
      match Eio.Stream.take t.buffer with
      | State state -> Some state
      | End ->
          t.finished <- true;
          None

  let dropped t = t.dropped

  let close t =
    t.detach ();
    if not t.ended then (
      while Option.is_some (Eio.Stream.take_nonblocking t.buffer) do
        ()
      done;
      finish t)
end

(* Closing the mailbox is what stops admission, wakes the fibers blocked on a full
   mailbox (their message is then not sent), and lets the stopping actor drain what is
   left. *)
type ('state, 'msg, 'reply, 'e) t = {
  mailbox : (('msg, ('reply, 'e) result) envelope, unit) Channel.t;
  mutable state : 'state;
  mutable stopped : bool;
  mutable subscribers : 'state Changes.t list;
}

let state t = t.state

let enqueue t envelope =
  match Channel.send t.mailbox envelope with Ok () -> true | Error _ -> false

let tell t msg = ignore (enqueue t { msg; reply = None })

let try_tell t msg =
  match Channel.try_send t.mailbox { msg; reply = None } with
  | Ok () -> true
  | Error _ -> false

let ask ?timeout (t : (_, _, _, ([> `Actor_stopped | `Timeout ] as 'e)) t) msg :
    (_, 'e) result =
  let promise, resolver = Eio.Promise.create () in
  if not (enqueue t { msg; reply = Some { resolver; settled = false } }) then
    Error `Actor_stopped
  else
    let wait () = Eio.Promise.await promise in
    match timeout with
    | None -> wait ()
    | Some (clock, limit) -> Timeout.timeout ~clock limit wait

let changes ?(capacity = 64) t =
  if capacity < 1 then invalid_arg "Ox.Actor.changes: capacity must be at least 1";
  let subscription = Changes.create capacity in
  if t.stopped then Changes.finish subscription
  else (
    t.subscribers <- subscription :: t.subscribers;
    subscription.detach <-
      (fun () ->
        t.subscribers <- List.filter (fun other -> other != subscription) t.subscribers));
  subscription

(* The mailbox is closed and every waiter answered before [on_stop] runs. A fiber blocked
   on a full mailbox is woken by the close and its message is not sent. *)
let stop t in_flight =
  t.stopped <- true;
  Channel.done_ t.mailbox;
  Option.iter (fun cell -> answer cell (Error `Actor_stopped)) !in_flight;
  in_flight := None;
  let rec drain () =
    match Channel.try_receive t.mailbox with
    | Ok { reply; _ } ->
        Option.iter (fun cell -> answer cell (Error `Actor_stopped)) reply;
        drain ()
    | Error _ -> ()
  in
  drain ();
  let subscribers = t.subscribers in
  t.subscribers <- [];
  List.iter Changes.finish subscribers

let create ?(capacity = 1024) ?on_stop ~sw ~init
    ~(handle :
       'state -> 'msg -> ('state * 'reply, ([> `Actor_stopped | `Timeout ] as 'e)) result)
    () : ('state, 'msg, 'reply, 'e) t =
  if capacity < 1 then invalid_arg "Ox.Actor.create: capacity must be at least 1";
  Eio.Switch.check sw;
  let t =
    {
      mailbox = Channel.create ~capacity ();
      state = init;
      stopped = false;
      subscribers = [];
    }
  in
  let in_flight = ref None in
  let rec loop () =
    Eio.Fiber.check ();
    match Channel.receive t.mailbox with
    | Error _ -> ()
    | Ok { msg; reply } ->
        in_flight := reply;
        (match Eio.Cancel.protect (fun () -> handle t.state msg) with
        | Ok (next, value) ->
            t.state <- next;
            Option.iter (fun cell -> answer cell (Ok value)) reply;
            List.iter (fun subscription -> Changes.push subscription next) t.subscribers
        | Error e -> Option.iter (fun cell -> answer cell (Error e)) reply);
        in_flight := None;
        loop ()
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      match loop () with
      | exception ex -> (
          let bt = Printexc.get_raw_backtrace () in
          stop t in_flight;
          match on_stop with
          | None -> Printexc.raise_with_backtrace ex bt
          | Some on_stop -> (
              match Eio.Cancel.protect (fun () -> on_stop t.state) with
              | () -> Printexc.raise_with_backtrace ex bt
              | exception failure -> (
                  let failure_bt = Printexc.get_raw_backtrace () in
                  match ex with
                  | Eio.Cancel.Cancelled _ ->
                      Printexc.raise_with_backtrace failure failure_bt
                  | _ -> raise (Eio.Exn.Multiple [ (ex, bt); (failure, failure_bt) ]))))
      | () ->
          stop t in_flight;
          `Stop_daemon);
  t
