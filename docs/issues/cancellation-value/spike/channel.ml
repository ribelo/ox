type 'e state = Open | Finished | Failed of 'e
type 'e closed = [ `Done | `Error of 'e ]

type ('a, 'e) t = {
  capacity : int;
  items : 'a Queue.t;
  mutable state : 'e state;
  changed : Eio.Condition.t;
}

let create ?(capacity = 16) () =
  if capacity < 1 then invalid_arg "Channel.create: capacity must be at least 1";
  { capacity; items = Queue.create (); state = Open; changed = Eio.Condition.create () }

let changed t = Eio.Condition.broadcast t.changed

let try_send t v =
  match t.state with
  | Finished -> Error `Done
  | Failed e -> Error (`Error e)
  | Open ->
      if Queue.length t.items >= t.capacity then Error `Full
      else (
        Queue.add v t.items;
        changed t;
        Ok ())

let try_receive t =
  match t.state with
  | Failed e -> Error (`Error e)
  | Open | Finished -> (
      match Queue.take_opt t.items with
      | Some v ->
          changed t;
          Ok v
      | None -> ( match t.state with Finished -> Error `Done | _ -> Error `Empty))

let wait_changed t = Eio.Condition.await_no_mutex t.changed

let rec send t v =
  match try_send t v with
  | Ok () -> Ok ()
  | Error `Full ->
      wait_changed t;
      send t v
  | Error ((`Done | `Error _) as closed) -> Error closed

let receive ~cancel t =
  (* Termination remains Eio's exception, even for a pre-canceled token. *)
  Eio.Fiber.check ();
  Cancellation.attach cancel t.changed;
  let rec loop () =
    Eio.Fiber.check ();
    if Cancellation.is_canceled cancel then Error `Canceled
    else match try_receive t with
    | Ok _ as ok -> ok
    | Error `Empty -> wait_changed t; loop ()
    | Error ((`Done | `Error _) as closed) -> Error closed
  in
  match loop () with
  | value -> Cancellation.detach cancel t.changed; value
  | exception ex ->
      let bt = Printexc.get_raw_backtrace () in
      Cancellation.detach cancel t.changed;
      Printexc.raise_with_backtrace ex bt

let done_ t =
  match t.state with
  | Open ->
      t.state <- Finished;
      changed t
  | Finished | Failed _ -> ()

let error t e =
  match t.state with
  | Failed _ -> ()
  | Open | Finished ->
      t.state <- Failed e;
      Queue.clear t.items;
      changed t
