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

let cursor =
  Runtime_events.start ();
  Runtime_events.create_cursor None

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
    (Eio.Time.now clock +. Eta.Duration.to_seconds_float duration);
  Eio.Fiber.yield ()

type ('a, 'e) handle = ('a, 'e) Eta.Exit.t Eio.Promise.t

let fork_run ~sw fn =
  let promise, resolve = Eio.Promise.create () in
  Eio.Fiber.fork ~sw (fun () -> Eio.Promise.resolve resolve (Eta.Scope.run fn));
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
  let open Eta.Cause in
  match (a, b) with
  | Fail a, Fail b -> eq a b
  | Die (a, _), Die (b, _) -> String.equal (Printexc.to_string a) (Printexc.to_string b)
  | Interrupt a, Interrupt b -> (
      match (a, b) with
      | None, None -> true
      | Some a, Some b -> Eta.Interrupt_id.equal a b
      | _ -> false)
  | Finalizer a, Finalizer b -> cause_equal eq a b
  | Suppressed a, Suppressed b ->
      cause_equal eq a.primary b.primary && cause_equal eq a.finalizer b.finalizer
  | Concurrent a, Concurrent b ->
      List.length a = List.length b && List.for_all2 (cause_equal eq) a b
  | _ -> false

let cause error =
  Alcotest.testable
    (Eta.Cause.pp (Alcotest.pp error))
    (cause_equal (Alcotest.equal error))

let exit value error =
  Alcotest.testable
    (Eta.Exit.pp (Alcotest.pp value) (Alcotest.pp error))
    (fun a b ->
      match (a, b) with
      | Eta.Exit.Success a, Eta.Exit.Success b -> Alcotest.equal value a b
      | Eta.Exit.Failure a, Eta.Exit.Failure b -> cause_equal (Alcotest.equal error) a b
      | _ -> false)

let flow_pair ?(label = "scripted") chunks =
  let source = Eio_mock.Flow.make (label ^ ":source") in
  Eio_mock.Flow.on_read source
    (List.map (fun chunk -> `Return chunk) chunks @ [ `Raise End_of_file ]);
  (source, Eio_mock.Flow.make (label ^ ":sink"))

module Process = struct
  type script = Exit of Eio.Process.exit_status | Block_until_signal

  type spawn = {
    argv : string list;
    env : string array;
    cwd : Eio.Fs.dir_ty Eio.Path.t option;
    pgid : int option;
    executable : string;
    fds : (int * Eio_unix.Fd.t * Eio_unix.Private.Fork_action.blocking) list;
  }

  type t = {
    mutable scripts : script list;
    mutable spawn_log : spawn list;
    mutable signal_log : int list;
    mutable next_pid : int;
  }

  let make scripts = { scripts; spawn_log = []; signal_log = []; next_pid = 1000 }
  let spawns t = List.rev t.spawn_log
  let signals t = List.rev t.signal_log

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

    let signal c n =
      match c.status with
      | Some _ -> ()
      | None ->
          c.owner.record_signal n;
          let status = `Signaled n in
          c.status <- Some status;
          Eio.Promise.resolve c.resolver status
  end

  let spawn_unix t ~sw ?cwd ?pgid ~env ~fds ~executable argv =
    let script =
      match t.scripts with
      | script :: rest ->
          t.scripts <- rest;
          script
      | [] -> invalid_arg "Eta_test.Process: no scripted exit left"
    in
    t.spawn_log <-
      { argv; env = Array.copy env; cwd; pgid; executable; fds } :: t.spawn_log;
    let finished, resolver = Eio.Promise.create () in
    let status =
      match script with
      | Exit status ->
          Eio.Promise.resolve resolver status;
          Some status
      | Block_until_signal -> None
    in
    let child =
      {
        Child.pid = t.next_pid;
        owner = { record_signal = (fun n -> t.signal_log <- n :: t.signal_log) };
        status;
        finished;
        resolver;
      }
    in
    t.next_pid <- t.next_pid + 1;
    Eio.Switch.on_release sw (fun () -> Child.signal child Sys.sigkill);
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
        | None, [] -> invalid_arg "Eta_test.Process: missing executable and argv"
      in
      let env = Option.value env ~default:(Unix.environment ()) in
      let fd_or default = function
        | None -> default
        | Some flow -> (
            match Eio_unix.Resource.fd_opt flow with
            | Some fd -> fd
            | None ->
                invalid_arg
                  "Eta_test.Process: only FD-backed standard streams are supported")
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
