type exit = Exited of int | Signaled of int
type error = [ `Invalid_fd of int | `Duplicate_fd of int ]
type output = Pipe | Discard

type t = {
  process : Eio_unix.Process.ty Eio.Resource.t;
  stdout : Eio.Flow.source_ty Eio.Resource.t option;
  stderr : Eio.Flow.source_ty Eio.Resource.t option;
  request : unit Eio.Promise.u;
  finished : exit Eio.Promise.or_exn;
  mutable reaped : bool;
}

let stdout t = t.stdout
let pid t = Eio.Process.pid t.process
let stderr t = t.stderr
let status = function `Exited n -> Exited n | `Signaled n -> Signaled n

let await t =
  let result = status (Eio.Process.await t.process) in
  t.reaped <- true;
  result

let signal t signum =
  if (not t.reaped) && not (Eio.Promise.is_resolved t.finished) then
    Eio.Process.signal t.process signum

let stop t =
  Eio.Cancel.protect (fun () ->
      ignore (Eio.Promise.try_resolve t.request ());
      Eio.Promise.await_exn t.finished)

let validate fds =
  let rec go seen = function
    | [] -> Ok ()
    | (n, _) :: _ when n < 3 -> Error (`Invalid_fd n)
    | (n, _) :: _ when List.mem n seen -> Error (`Duplicate_fd n)
    | (n, _) :: rest -> go (n :: seen) rest
  in
  go [] fds

let spawn ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >)
    ~sw ~clock ~mgr ~argv ?env ?cwd ?(stdout = Discard) ?(stderr = Discard) ~grace ~fds ()
    =
  match validate fds with
  | Error _ as error -> error
  | Ok () -> (
      let ready, ready_u = Eio.Promise.create () in
      let request, request_u = Eio.Promise.create () in
      let finished, finished_u = Eio.Promise.create () in
      Eio.Fiber.fork_daemon ~sw (fun () ->
          let outcome =
            try
              Ok
                (Eio.Switch.run_protected (fun private_sw ->
                     let fd flow =
                       match Eio_unix.Resource.fd_opt flow with
                       | Some fd -> fd
                       | None -> failwith "Eio Unix pipe has no FD"
                     in
                     let output mode =
                       match mode with
                       | Pipe ->
                           let input, write = Eio_unix.pipe sw in
                           ( Some (input :> Eio.Flow.source_ty Eio.Resource.t),
                             fd write,
                             Some write )
                       | Discard ->
                           let raw = Ox_caps.Cap_unix.open_dev_null ~caps () in
                           let null =
                             Eio_unix.Fd.of_unix ~sw:private_sw ~close_unix:true raw
                           in
                           (None, null, None)
                     in
                     let out, out_fd, close_out = output stdout in
                     let err, err_fd, close_err = output stderr in
                     let mapped =
                       [
                         (0, Eio_unix.Fd.stdin, `Preserve_blocking);
                         (1, out_fd, `Blocking);
                         (2, err_fd, `Blocking);
                       ]
                       (* Mapped descriptors are the child's own ends: a child
                          expects blocking I/O on them, and Eio's pipes are
                          non-blocking, which Chrome treats as a dead pipe. *)
                       @ List.map (fun (n, fd) -> (n, fd, `Blocking)) fds
                     in
                     let process =
                       Eio_unix.Process.spawn_unix ~sw:private_sw mgr ?env ?cwd
                         ~fds:mapped argv
                     in
                     Option.iter Eio.Resource.close close_out;
                     Option.iter Eio.Resource.close close_err;
                     let child =
                       {
                         process;
                         stdout = out;
                         stderr = err;
                         request = request_u;
                         finished;
                         reaped = false;
                       }
                     in
                     Eio.Promise.resolve ready_u (Ok child);
                     Eio.Promise.await request;
                     Eio.Cancel.protect (fun () ->
                         Eio.Process.signal process Sys.sigterm;
                         let prior =
                           if Ox.Duration.is_zero grace then None
                           else
                             match
                               Ox.Timeout.timeout ~clock grace (fun () ->
                                   Ok (Eio.Process.await process))
                             with
                             | Ok x -> Some x
                             | Error `Timeout -> None
                         in
                         match prior with
                         | Some x -> status x
                         | None ->
                             Eio.Process.signal process Sys.sigkill;
                             status (Eio.Process.await process))))
            with ex -> Error ex
          in
          (match outcome with
          | Ok exit -> Eio.Promise.resolve_ok finished_u exit
          | Error ex ->
              if not (Eio.Promise.is_resolved ready) then
                Eio.Promise.resolve ready_u (Error ex)
              else Eio.Promise.resolve_error finished_u ex);
          `Stop_daemon);
      (* This cancellable daemon is the outer-switch cancellation bridge. Its
       protected sibling never inherits the parent's cancellation. *)
      Eio.Fiber.fork_daemon ~sw (fun () ->
          (try
             (* ^nlint-hxar: this bridge only waits; stop observes the retained defect. *)
             let _finished_result = (Eio.Promise.await finished : (exit, exn) result) in
             ()
           with Eio.Cancel.Cancelled _ -> ignore (Eio.Promise.try_resolve request_u ()));
          `Stop_daemon);
      match Eio.Promise.await ready with
      | Ok t ->
          Eio.Switch.on_release sw (fun () -> ignore (stop t));
          Ok t
      | Error ex -> raise ex)
