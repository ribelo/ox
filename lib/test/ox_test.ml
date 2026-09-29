type env =
  < clock : Eio_mock.Clock.t
  ; mono_clock : Eio_mock.Clock.Mono.t
  ; fs : Eio.Fs.dir_ty Eio.Path.t
  ; cwd : Eio.Fs.dir_ty Eio.Path.t
  ; net : [ `Unix | `Generic ] Eio.Net.ty Eio.Resource.t
  ; process_mgr : Eio_unix.Process.mgr_ty Eio.Resource.t
  ; backend_id : string >

(* Eio emits both creation and exit on every fiber, including forks not made here. *)
let live : (int, int) Hashtbl.t = Hashtbl.create 128
let serial = ref 0
let lost = ref false

let callbacks =
  Eio_runtime_events.add_callbacks
    (fun _ _ -> function
      | `Create (id, `Fiber_in _) ->
          incr serial;
          Hashtbl.replace live id !serial
      | `Exit_fiber id -> Hashtbl.remove live id
      | _ -> ())
    (Runtime_events.Callbacks.create ~lost_events:(fun _ _ -> lost := true) ())

(* The census reads this process's own runtime_events ring, which the runtime names
   [<pid>.events] after its pid. The ring's directory is fixed before any OCaml code runs:
   the runtime reads OCAML_RUNTIME_EVENTS_DIR in [caml_runtime_events_init] at startup, so
   setting that variable here cannot move this process's ring. For the unset case the
   runtime keeps the bare "[<pid>.events]" fallback, whose open resolves against the
   working directory in effect when the ring is created, and the census owns that moment:
   it creates the ring inside a private temporary directory by switching there for [start]
   and for the cursor that maps the ring by name, then switching straight back. *)
let ring_dir =
  match Sys.getenv_opt "OCAML_RUNTIME_EVENTS_DIR" with
  | Some _ -> None
  | None -> (
      try Some (Filename.temp_dir "ox-test-events-" "") with Sys_error _ -> None)

let start_census () =
  match ring_dir with
  | None ->
      Runtime_events.start ();
      Runtime_events.create_cursor None
  | Some dir ->
      let cwd = Sys.getcwd () in
      Sys.chdir dir;
      Fun.protect
        ~finally:(fun () -> Sys.chdir cwd)
        (fun () ->
          Runtime_events.start ();
          Runtime_events.create_cursor None)

let cursor = start_census ()

(* The runtime's own exit-time unlink resolves that relative fallback path against the
   working directory restored above, so it cannot take this ring with it; the census
   removes the directory it created instead. *)
let remove_ring_dir dir =
  (try
     Array.iter
       (fun name -> try Sys.remove (Filename.concat dir name) with Sys_error _ -> ())
       (Sys.readdir dir)
   with Sys_error _ -> ());
  try Sys.rmdir dir with Sys_error _ -> ()

let () =
  match ring_dir with None -> () | Some dir -> at_exit (fun () -> remove_ring_dir dir)

let drain () =
  while Runtime_events.read_poll cursor callbacks None > 0 do
    ()
  done;
  if !lost then Alcotest.fail "fiber census lost runtime events"

let baseline = ref 0

let with_census f =
  drain ();
  let before = !serial in
  let _ = f () in
  drain ();
  Hashtbl.fold
    (fun _ created count -> if created > before then count + 1 else count)
    live 0

let run fn =
  Eio_main.run @@ fun real ->
  let clock = Eio_mock.Clock.make () in
  let mono_clock = Eio_mock.Clock.Mono.make () in
  let env : env =
    object
      method clock = clock
      method mono_clock = mono_clock
      method fs = real#fs
      method cwd = real#cwd
      method net = real#net
      method process_mgr = real#process_mgr
      method backend_id = real#backend_id
    end
  in
  Eio.Switch.run (fun sw ->
      drain ();
      baseline := !serial;
      fn env sw)

let advance clock duration =
  Eio_mock.Clock.set_time clock
    (Eio.Time.now clock +. Ox.Duration.to_seconds_float duration);
  Eio.Fiber.yield ()

type ('a, 'e) handle = ('a, 'e) Ox.Exit.t Eio.Promise.t

let fork_run ~sw fn =
  let promise, resolve = Eio.Promise.create () in
  Eio.Fiber.fork ~sw (fun () -> Eio.Promise.resolve resolve (Ox.Scope.run fn));
  promise

let await = Eio.Promise.await

let assert_no_fibers_left () =
  drain ();
  let leaked =
    Hashtbl.fold
      (fun _ created count -> if created > !baseline then count + 1 else count)
      live 0
  in
  if leaked <> 0 then Alcotest.failf "leaked %d Eio fiber(s)" leaked

let rec cause_equal eq a b =
  let open Ox.Cause in
  match (a, b) with
  | Fail a, Fail b -> eq a b
  | Die (a, _), Die (b, _) -> String.equal (Printexc.to_string a) (Printexc.to_string b)
  | Interrupt a, Interrupt b -> (
      match (a, b) with
      | None, None -> true
      | Some a, Some b -> Ox.Interrupt_id.equal a b
      | _ -> false)
  | Finalizer a, Finalizer b -> cause_equal eq a b
  | Suppressed a, Suppressed b ->
      cause_equal eq a.primary b.primary && cause_equal eq a.finalizer b.finalizer
  | Concurrent a, Concurrent b ->
      List.length a = List.length b && List.for_all2 (cause_equal eq) a b
  | _ -> false

let cause error =
  Alcotest.testable (Ox.Cause.pp (Alcotest.pp error)) (cause_equal (Alcotest.equal error))

let exit value error =
  Alcotest.testable
    (Ox.Exit.pp (Alcotest.pp value) (Alcotest.pp error))
    (fun a b ->
      match (a, b) with
      | Ox.Exit.Success a, Ox.Exit.Success b -> Alcotest.equal value a b
      | Ox.Exit.Failure a, Ox.Exit.Failure b -> cause_equal (Alcotest.equal error) a b
      | _ -> false)

let flow_pair ?(label = "scripted") chunks =
  let source = Eio_mock.Flow.make (label ^ ":source") in
  Eio_mock.Flow.on_read source
    (List.map (fun chunk -> `Return chunk) chunks @ [ `Raise End_of_file ]);
  (source, Eio_mock.Flow.make (label ^ ":sink"))

module Process = struct
  type stream = Stdout | Stderr
  type chunk = { stream : stream; data : string; after : Ox.Duration.t }

  type script =
    | Exit of Eio.Process.exit_status
    | Block_until_signal
    | Output of chunk list * script

  type spawn = {
    argv : string list;
    env : string array;
    cwd : Eio.Fs.dir_ty Eio.Path.t option;
    pgid : int option;
    executable : string;
    fds : (int * Eio_unix.Fd.t * Eio_unix.Private.Fork_action.blocking) list;
  }

  (* The script's clock, kept as its two operations so that [t] stays monomorphic. *)
  type timer = { now : unit -> float; sleep_until : float -> unit }

  type t = {
    mutable scripts : script list;
    mutable spawn_log : spawn list;
    mutable signal_log : int list;
    mutable next_pid : int;
    timer : timer option;
  }

  let rec delayed = function
    | Exit _ | Block_until_signal -> false
    | Output (chunks, rest) ->
        List.exists (fun chunk -> not (Ox.Duration.is_zero chunk.after)) chunks
        || delayed rest

  let make ?clock scripts =
    if Option.is_none clock && List.exists delayed scripts then
      invalid_arg "Ox_test.Process: a delayed chunk needs a clock";
    let timer =
      Option.map
        (fun clock ->
          {
            now = (fun () -> Eio.Time.now clock);
            sleep_until = (fun due -> Eio.Time.sleep_until clock due);
          })
        clock
    in
    { scripts; spawn_log = []; signal_log = []; next_pid = 1000; timer }

  let spawns t = List.rev t.spawn_log
  let signals t = List.rev t.signal_log

  (* Nested [Output] is the same run of chunks; only the last script terminates. *)
  let rec plan = function
    | Exit status -> ([], `Exit status)
    | Block_until_signal -> ([], `Block)
    | Output (chunks, rest) ->
        let rest_chunks, terminal = plan rest in
        (chunks @ rest_chunks, terminal)

  module Child = struct
    type tag = [ `Generic | `Unix ]

    type t = {
      pid : int;
      owner : t_owner;
      mutable status : Eio.Process.exit_status option;
      finished : Eio.Process.exit_status Eio.Promise.t;
      resolver : Eio.Process.exit_status Eio.Promise.u;
    }

    and t_owner = { record_signal : int -> unit }

    let pid c = c.pid

    let await c =
      match c.status with Some status -> status | None -> Eio.Promise.await c.finished

    let finish c status =
      match c.status with
      | Some _ -> ()
      | None ->
          c.status <- Some status;
          Eio.Promise.resolve c.resolver status

    let signal c n =
      match c.status with
      | Some _ -> ()
      | None ->
          c.owner.record_signal n;
          finish c (`Signaled n)
  end

  let descriptor = function Stdout -> 1 | Stderr -> 2
  let name = function Stdout -> "stdout" | Stderr -> "stderr"
  let prints stream chunks = List.exists (fun chunk -> chunk.stream = stream) chunks

  (* The spawn borrows its descriptors, so keep a private write end: closing the caller's
     copy when [spawn_unix] returns must not take the child's away. *)
  let borrow fds stream =
    match List.find_opt (fun (n, _, _) -> n = descriptor stream) fds with
    | None ->
        invalid_arg
          (Printf.sprintf "Ox_test.Process: no descriptor mapped to the child's %s"
             (name stream))
    | Some (_, fd, _) ->
        Eio_unix.Fd.use fd
          (fun unix_fd ->
            let copy = Unix.dup unix_fd in
            Unix.set_close_on_exec copy;
            copy)
          ~if_closed:(fun () ->
            invalid_arg
              (Printf.sprintf "Ox_test.Process: the child's %s is already closed"
                 (name stream)))

  (* Descriptors are Eio's, so non-blocking: a full pipe waits instead of spinning, and a
     reader that closed its end ends this chunk, as SIGPIPE would end a real child. *)
  let write_all fd data =
    let buffer = Bytes.of_string data in
    let total = Bytes.length buffer in
    let rec loop written =
      if written < total then
        match Unix.write fd buffer written (total - written) with
        | progress -> loop (written + progress)
        | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
            Eio_unix.await_writable fd;
            loop written
        | exception Unix.Unix_error ((Unix.EPIPE | Unix.EBADF), _, _) -> ()
    in
    loop 0

  (* Chunks are timed from the spawn, so a test that advances the clock before this fiber
     is scheduled still sees them: a due time already reached does not wait. *)
  let schedule timer chunks =
    match timer with
    | None -> List.map (fun chunk -> (chunk, None)) chunks
    | Some timer ->
        let spawned = timer.now () in
        let _, scheduled =
          List.fold_left
            (fun (at, scheduled) chunk ->
              let at = at +. Ox.Duration.to_seconds_float chunk.after in
              (at, (chunk, Some (spawned +. at)) :: scheduled))
            (0., []) chunks
        in
        List.rev scheduled

  (* One daemon per output script, owned by the spawn's switch: Eio cancels daemons when
     the switch's own work ends, which is the retirement signal. The caller's copy of the
     write ends closes when [spawn_unix] returns; this daemon's copy closes when the
     script ends or the daemon is cancelled, so a reader sees everything up to that point
     followed by EOF. *)
  let start_output t ~sw child fds chunks terminal =
    let outputs =
      List.filter_map
        (fun stream ->
          if prints stream chunks then Some (stream, borrow fds stream) else None)
        [ Stdout; Stderr ]
    in
    let scheduled = schedule t.timer chunks in
    Eio.Fiber.fork_daemon ~sw (fun () ->
        Fun.protect
          ~finally:(fun () ->
            List.iter
              (fun (_, fd) -> try Unix.close fd with Unix.Unix_error _ -> ())
              outputs)
          (fun () ->
            List.iter
              (fun (chunk, due) ->
                (match (due, t.timer) with
                | Some due, Some timer -> timer.sleep_until due
                | _ -> ());
                if child.Child.status = None then
                  write_all (List.assoc chunk.stream outputs) chunk.data)
              scheduled;
            match terminal with
            | `Exit status -> Child.finish child status
            | `Block ->
                (* A blocked child holds the write ends open until it is signalled, and
                   the switch cancels this daemon once the child is retired. *)
                ignore (Eio.Promise.await child.Child.finished : Eio.Process.exit_status));
        `Stop_daemon)

  let spawn_unix t ~sw ?cwd ?pgid ~env ~fds ~executable argv =
    let script =
      match t.scripts with
      | script :: rest ->
          t.scripts <- rest;
          script
      | [] -> invalid_arg "Ox_test.Process: no scripted exit left"
    in
    t.spawn_log <-
      { argv; env = Array.copy env; cwd; pgid; executable; fds } :: t.spawn_log;
    let chunks, terminal = plan script in
    let finished, resolver = Eio.Promise.create () in
    let child =
      {
        Child.pid = t.next_pid;
        owner = { record_signal = (fun n -> t.signal_log <- n :: t.signal_log) };
        status = None;
        finished;
        resolver;
      }
    in
    t.next_pid <- t.next_pid + 1;
    Eio.Switch.on_release sw (fun () -> Child.signal child Sys.sigkill);
    (match (chunks, terminal) with
    | [], `Exit status -> Child.finish child status
    | [], `Block -> ()
    | chunks, terminal -> start_output t ~sw child fds chunks terminal);
    Eio.Resource.T (child, Eio.Process.Pi.process (module Child))

  module Mgr = struct
    type nonrec t = t
    type tag = [ `Generic | `Unix ]

    let pipe _ ~sw =
      (Eio_unix.pipe sw
        :> [ Eio.Resource.close_ty | Eio.Flow.source_ty ] Eio.Resource.t
           * [ Eio.Resource.close_ty | Eio.Flow.sink_ty ] Eio.Resource.t)

    let spawn_unix = spawn_unix

    let spawn t ~sw ?cwd ?stdin ?stdout ?stderr ?env ?executable argv =
      let executable =
        match (executable, argv) with
        | Some exe, _ -> exe
        | None, exe :: _ -> exe
        | None, [] -> invalid_arg "Ox_test.Process: missing executable and argv"
      in
      let env = Option.value env ~default:(Unix.environment ()) in
      let fd_or default = function
        | None -> default
        | Some flow -> (
            match Eio_unix.Resource.fd_opt flow with
            | Some fd -> fd
            | None ->
                invalid_arg
                  "Ox_test.Process: only FD-backed standard streams are supported")
      in
      let fds =
        [
          (0, fd_or Eio_unix.Fd.stdin stdin, `Blocking);
          (1, fd_or Eio_unix.Fd.stdout stdout, `Blocking);
          (2, fd_or Eio_unix.Fd.stderr stderr, `Blocking);
        ]
      in
      spawn_unix t ~sw ?cwd ~env ~fds ~executable argv
  end

  let mgr t = Eio.Resource.T (t, Eio_unix.Process.Pi.mgr_unix (module Mgr))
end
