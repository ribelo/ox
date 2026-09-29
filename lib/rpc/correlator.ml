type close_reason = [ `Eof | `Read_failed of exn | `Closed ]

type error =
  [ `Transport_closed of close_reason | `Write_failed of exn | `Timeout | `Id_exhausted ]

type stats = { pending : int; buffered_notifications : int; dropped_notifications : int }
type 'msg notification = Message of 'msg | Closed of close_reason

type 'msg slot = {
  reply : ('msg, error) result Eio.Promise.t;
  resolve : ('msg, error) result Eio.Promise.u;
}

type 'msg t = {
  timeout : Ox.Duration.t -> (unit -> ('msg, error) result) -> ('msg, error) result;
  write : 'msg -> unit;
  id : 'msg -> int option;
  set_id : 'msg -> int -> 'msg;
  session : 'msg -> string option;
  slots : (int * string option, 'msg slot) Hashtbl.t;
  notices : 'msg notification Eio.Stream.t;
  max_notifications : int;
  mutable dropped : int;
  mutable next_id : int;
  mutable closed : close_reason option;
  write_lock : Eio.Mutex.t;
  mutable reader_cancel : Eio.Cancel.t option;
  reader_done : unit Eio.Promise.t;
  reader_finished : unit Eio.Promise.u;
}

let settle t reason =
  match t.closed with
  | Some _ -> ()
  | None ->
      t.closed <- Some reason;
      Hashtbl.iter
        (fun _ slot ->
          Eio.Promise.resolve slot.resolve (Error (`Transport_closed reason)))
        t.slots;
      Hashtbl.clear t.slots;
      if Eio.Stream.length t.notices = t.max_notifications then (
        ignore (Eio.Stream.take_nonblocking t.notices);
        t.dropped <- t.dropped + 1);
      Eio.Stream.add t.notices (Closed reason)

let stats t =
  {
    pending = Hashtbl.length t.slots;
    buffered_notifications = Eio.Stream.length t.notices;
    dropped_notifications = t.dropped;
  }

let notifications t = t.notices

let offer t message =
  if Eio.Stream.length t.notices = t.max_notifications then (
    ignore (Eio.Stream.take_nonblocking t.notices);
    t.dropped <- t.dropped + 1);
  Eio.Stream.add t.notices (Message message)

let route t message =
  match t.closed with
  | Some _ -> ()
  | None -> (
      match t.id message with
      | Some id -> (
          let key = (id, t.session message) in
          match Hashtbl.find_opt t.slots key with
          | Some slot ->
              Hashtbl.remove t.slots key;
              Eio.Promise.resolve slot.resolve (Ok message)
          | None -> offer t message)
      | None -> offer t message)

let close t =
  settle t `Closed;
  if not (Eio.Promise.is_resolved t.reader_done) then
    Option.iter
      (fun ctx -> Eio.Cancel.cancel ctx (Failure "ox_rpc: closed"))
      t.reader_cancel;
  Eio.Promise.await t.reader_done

let create ~sw ~clock ?(max_notifications = 1024) ~read ~write ~id ~set_id
    ?(session = fun _ -> None) () =
  if max_notifications <= 0 then invalid_arg "ox_rpc: max_notifications must be positive";
  let reader_done, reader_finished = Eio.Promise.create () in
  let t =
    {
      timeout = Ox.Timeout.timeout ~clock;
      write;
      id;
      set_id;
      session;
      slots = Hashtbl.create 32;
      notices = Eio.Stream.create max_notifications;
      max_notifications;
      dropped = 0;
      next_id = 1;
      closed = None;
      write_lock = Eio.Mutex.create ();
      reader_cancel = None;
      reader_done;
      reader_finished;
    }
  in
  Eio.Switch.on_release sw (fun () -> settle t `Closed);
  Eio.Fiber.fork_daemon ~sw (fun () ->
      Fun.protect
        ~finally:(fun () ->
          t.reader_cancel <- None;
          Eio.Promise.resolve t.reader_finished ())
        (fun () ->
          try
            Eio.Cancel.sub (fun ctx ->
                t.reader_cancel <- Some ctx;
                let rec loop () =
                  let next =
                    try Ok (read ()) with
                    | Eio.Cancel.Cancelled _ as exn -> raise exn
                    | exn -> Error exn
                  in
                  match next with
                  | Ok (Some message) ->
                      route t message;
                      loop ()
                  | Ok None -> settle t `Eof
                  | Error exn -> settle t (`Read_failed exn)
                in
                loop ())
          with Eio.Cancel.Cancelled _ -> ());
      `Stop_daemon);
  t

let call t ?session ?deadline message =
  let run () =
    match t.closed with
    | Some reason -> Error (`Transport_closed reason)
    | None when t.next_id = 0 -> Error `Id_exhausted
    | None ->
        let id = t.next_id in
        t.next_id <- (if id = max_int then 0 else id + 1);
        let key =
          (id, match session with Some _ -> session | None -> t.session message)
        in
        let reply, resolve = Eio.Promise.create () in
        let slot = { reply; resolve } in
        Hashtbl.add t.slots key slot;
        Fun.protect
          ~finally:(fun () ->
            match Hashtbl.find_opt t.slots key with
            | Some current when current == slot -> Hashtbl.remove t.slots key
            | _ -> ())
          (fun () ->
            let outbound = t.set_id message id in
            let written =
              try
                Eio.Mutex.use_ro t.write_lock (fun () ->
                    (* A frame is written whole or not at all: cancelling the call
                       mid-write would leave a partial frame that corrupts every
                       later message on the stream. *)
                    Eio.Cancel.protect (fun () ->
                        match t.closed with None -> t.write outbound | Some _ -> ()));
                Ok ()
              with
              | Eio.Cancel.Cancelled _ as exn -> raise exn
              | exn -> Error (`Write_failed exn)
            in
            match written with
            | Error _ as error -> error
            | Ok () -> Eio.Promise.await reply)
  in
  match deadline with None -> run () | Some duration -> t.timeout duration run
