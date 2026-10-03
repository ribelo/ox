type spawn_error = Ox_process.Child.error
type reason = [ `Spawn of spawn_error | `Schedule_exhausted of Ox_process.Child.exit ]
type event = Started of int | Lost of int | Gave_up of reason Ox.Cause.t | Stopped
type phase = [ `Running | `Restarting | `Gave_up | `Stopped ]

type status = {
  generation : int;
  phase : phase;
  failure : string option;
  headed : bool;
  pid : int option;
}

type backoff = {
  initial : Ox.Duration.t;
  cap : Ox.Duration.t;
  factor : float;
  attempts : int;
}

let default_backoff =
  {
    initial = Ox.Duration.seconds 1;
    cap = Ox.Duration.seconds 30;
    factor = 2.0;
    attempts = 10;
  }

type config = {
  binary : string;
  profile_dir : string;
  workspace : string;
  grace : Ox.Duration.t;
  backoff : backoff;
  headless : bool;
  window_size : string;
}

let make ~binary ~profile_dir ~workspace ?(grace = Ox.Duration.seconds 5)
    ?(backoff = default_backoff) ?(headless = false) ?(window_size = "1366,900") () =
  { binary; profile_dir; workspace; grace; backoff; headless; window_size }

(* chrome-9ex7 daily-a341: the operator signs in to their own accounts in this browser,
   so nothing a page can see may differ from Chrome started by hand. The debugging pipe
   switch alone turns on Blink's AutomationControlled feature in every renderer, which
   sets navigator.webdriver = true on every tab and makes Google's sign-in refuse the
   browser ("This browser or app may not be secure", /v3/signin/rejected). Disabling
   that one feature restores webdriver = false and adds nothing a page can observe. *)
let argv config =
  [
    config.binary;
    "--user-data-dir=" ^ config.profile_dir;
    "--no-first-run";
    "--no-default-browser-check";
    "--hide-crash-restore-bubble";
    "--remote-debugging-pipe";
    "--disable-blink-features=AutomationControlled";
    (* daily-a341: Chrome answers that flag with an "unsupported command-line flag …
       stability and security will suffer" infobar on every launch of the headed
       service. --test-type is the switch Chrome's own bad-flags prompt checks to stay
       silent; it changes nothing a page can see. *)
    "--test-type";
    (* pbk-eyya: an agent's tab is rarely the one in front. Without these, Chrome
       throttles an occluded or background renderer to few or no frames, so a wheel
       scroll lands seconds late (or after the next observation) and three scrolls read
       as a stall — books.toscrape.com's Default listing, page 4 and page 7. *)
    "--disable-backgrounding-occluded-windows";
    "--disable-renderer-backgrounding";
    "--disable-background-timer-throttling";
    "--class=leash";
  ]
  @
  if config.headless then [ "--headless=new"; "--window-size=" ^ config.window_size ]
  else []

type caps = < Ox_caps.Cap.fork ; Ox_caps.Cap.exec >

type 'clock deps = {
  clock : 'clock Eio.Time.clock;
  mgr : Eio_unix.Process.mgr_ty Eio.Resource.t;
  logger : Ox_observability.Logger.t;
  caps : caps;
}

type 'clock launch =
  sw:Eio.Switch.t ->
  clock:'clock Eio.Time.clock ->
  mgr:Eio_unix.Process.mgr_ty Eio.Resource.t ->
  config ->
  (Ox_process.Child.t * Cdp.transport, spawn_error) result

let fd flow =
  match Eio_unix.Resource.fd_opt flow with
  | Some fd -> fd
  | None -> invalid_arg "Chrome: pipe flow without a unix descriptor"

let launch_pipe ~caps ~sw ~clock ~mgr config =
  let child_read, parent_write = Eio_unix.pipe sw in
  let parent_read, child_write = Eio_unix.pipe sw in
  match
    Ox_process.Child.spawn ~caps ~sw ~clock ~mgr ~argv:(argv config) ~grace:config.grace
      ~stderr:Pipe
      ~fds:[ (3, fd child_read); (4, fd child_write) ]
      ()
  with
  | Error error -> Error error
  | Ok child ->
      Eio.Resource.close child_read;
      Eio.Resource.close child_write;
      Ok (child, { Cdp.read = parent_read; write = parent_write })

let schedule backoff =
  Ox.Schedule.both
    (Ox.Schedule.exponential ~factor:backoff.factor backoff.initial)
    (Ox.Schedule.recurs backoff.attempts)
  |> Ox.Schedule.max_interval backoff.cap

let signal_description signal =
  (* daily-c4cl: OCaml waitpid uses negative portable constants; kill(1) uses
     OS numbers. Leash runs on Linux. *)
  let signals =
    [
      (Sys.sighup, "SIGHUP", 1);
      (Sys.sigint, "SIGINT", 2);
      (Sys.sigquit, "SIGQUIT", 3);
      (Sys.sigill, "SIGILL", 4);
      (Sys.sigtrap, "SIGTRAP", 5);
      (Sys.sigabrt, "SIGABRT", 6);
      (Sys.sigbus, "SIGBUS", 7);
      (Sys.sigfpe, "SIGFPE", 8);
      (Sys.sigkill, "SIGKILL", 9);
      (Sys.sigusr1, "SIGUSR1", 10);
      (Sys.sigsegv, "SIGSEGV", 11);
      (Sys.sigusr2, "SIGUSR2", 12);
      (Sys.sigpipe, "SIGPIPE", 13);
      (Sys.sigalrm, "SIGALRM", 14);
      (Sys.sigterm, "SIGTERM", 15);
      (Sys.sigchld, "SIGCHLD", 17);
      (Sys.sigcont, "SIGCONT", 18);
      (Sys.sigstop, "SIGSTOP", 19);
      (Sys.sigtstp, "SIGTSTP", 20);
      (Sys.sigttin, "SIGTTIN", 21);
      (Sys.sigttou, "SIGTTOU", 22);
      (Sys.sigurg, "SIGURG", 23);
      (Sys.sigxcpu, "SIGXCPU", 24);
      (Sys.sigxfsz, "SIGXFSZ", 25);
      (Sys.sigvtalrm, "SIGVTALRM", 26);
      (Sys.sigprof, "SIGPROF", 27);
      (Sys.sigwinch, "SIGWINCH", 28);
      (Sys.sigio, "SIGIO", 29);
      (Sys.sigsys, "SIGSYS", 31);
    ]
  in
  match List.find_opt (fun (portable, _, _) -> portable = signal) signals with
  | Some (_, name, number) -> Printf.sprintf "%s / %d" name number
  | None -> Printf.sprintf "unknown signal %d" signal

let pp_reason ppf = function
  | `Spawn (`Invalid_fd fd) -> Format.fprintf ppf "invalid fd %d" fd
  | `Spawn (`Duplicate_fd fd) -> Format.fprintf ppf "duplicate fd %d" fd
  | `Schedule_exhausted (Ox_process.Child.Exited status) ->
      Format.fprintf ppf "chrome exited with status %d" status
  | `Schedule_exhausted (Ox_process.Child.Signaled signal) ->
      Format.fprintf ppf "chrome was killed by %s" (signal_description signal)

let render cause = Format.asprintf "%a" (Ox.Cause.pp_compact pp_reason) cause

module Log = struct
  let lifecycle logger level ~msg fields =
    Ox_observability.Logger.log logger level ~msg ~fields ()

  let int name value = (name, Ox_observability.Logger.Int value)
  let string name value = (name, Ox_observability.Logger.String value)
end

(* Each generation's stderr tail and the promise that says its reader reached end of input.
   The launching fiber adds an entry and the observer takes it when the generation is lost:
   two fibers, one table, so an {!Ox.Agent} owns it and serializes both (^nactor-75ef). *)
type tails = (int * Chrome_stderr.t * unit Eio.Promise.t) list

type state = {
  tails : tails Ox.Agent.t;
  signals :
    [ `Supervised of spawn_error Ox_process.Supervised.event | `Transport_closed of int ]
    Eio.Stream.t;
  events : event Eio.Stream.t;
  logger : Ox_observability.Logger.t;
  mutable phase : phase;
  mutable generation : int;
  mutable current : (int * Cdp.t) option;
  mutable failure : string option;
  headed : bool;
  mutable pending : Cdp.t option;
  mutable pid : int option;
  mutable closed_before_start : int option;
  mutable spawns : int;
  mutable abandoned : reason Ox.Cause.t option;
      (** A launch that failed (a typed spawn error or a defect) is not retried: the
          supervisor is stopped and the cause is what the service gave up with. *)
  stop_signal : unit Eio.Promise.t;
  resolve_stop : unit Eio.Promise.u;
  give_up : unit Eio.Promise.t;
  resolve_give_up : unit Eio.Promise.u;
  finished : unit Eio.Promise.t;
  resolve_finished : unit Eio.Promise.u;
}

type t = { state : state }

let publish state event =
  if Eio.Stream.length state.events >= 32 then
    ignore (Eio.Stream.take_nonblocking state.events);
  Eio.Stream.add state.events event

let lost state generation ~origin =
  state.current <- None;
  state.phase <- `Restarting;
  let taken =
    match
      Ox.Agent.get_and_update state.tails ~fn:(fun tails ->
          ( List.find_opt (fun (n, _, _) -> n = generation) tails,
            List.filter (fun (n, _, _) -> n <> generation) tails ))
    with
    | Ok taken -> taken
    | Error `Agent_stopped -> None
  in
  let stderr_lines =
    match taken with
    | Some (_, tail, drained) ->
        Eio.Promise.await drained;
        Chrome_stderr.lines tail
    | None -> []
  in
  publish state (Lost generation);
  Log.lifecycle state.logger Ox_observability.Logger.Warn ~msg:"chrome generation lost"
    [
      Log.int "generation" generation;
      Log.string "origin" origin;
      ( "stderr",
        Ox_observability.Logger.Json
          (`List (List.map (fun line -> `String line) stderr_lines)) );
    ]

let on_started state generation =
  let cdp = state.pending in
  state.pending <- None;
  state.generation <- generation;
  state.phase <- `Running;
  state.failure <- None;
  state.current <- Option.map (fun cdp -> (generation, cdp)) cdp;
  publish state (Started generation);
  Log.lifecycle state.logger Ox_observability.Logger.Info ~msg:"chrome started"
    [ Log.int "generation" generation ];
  match state.closed_before_start with
  | Some closed when closed = generation ->
      state.closed_before_start <- None;
      lost state generation ~origin:"transport before start"
  | _ -> ()

let on_exited state generation exit =
  if generation = state.generation && state.phase = `Running then
    let origin =
      match exit with
      | Ox_process.Child.Exited status -> "exit " ^ string_of_int status
      | Signaled signal -> signal_description signal
    in
    lost state generation ~origin

let on_transport_closed state generation =
  if generation = state.generation then
    begin if state.phase = `Running then lost state generation ~origin:"transport"
    end
  else if generation > state.generation then state.closed_before_start <- Some generation

let on_gave_up state cause =
  if state.phase = `Running then lost state state.generation ~origin:"gave up";
  let failure = render cause in
  state.phase <- `Gave_up;
  state.current <- None;
  state.failure <- Some failure;
  publish state (Gave_up cause);
  Log.lifecycle state.logger Ox_observability.Logger.Error ~msg:"chrome gave up"
    [ Log.string "cause" failure ]

let on_stopped state =
  state.phase <- `Stopped;
  state.current <- None;
  publish state Stopped;
  Log.lifecycle state.logger Ox_observability.Logger.Info ~msg:"chrome stopped" []

let rec observe state : [ `Stop_daemon ] =
  (match Eio.Stream.take state.signals with
  | `Supervised (Ox_process.Supervised.Started generation) -> on_started state generation
  | `Supervised (Exited (generation, exit)) -> on_exited state generation exit
  | `Supervised (Gave_up cause) -> on_gave_up state cause
  | `Supervised Stopped -> on_stopped state
  | `Transport_closed generation -> on_transport_closed state generation);
  observe state

(* The relaunch loop is one Permanent {!Ox.Supervisor} child: an incarnation is one Chrome
   generation, and it fails with the process's exit so the supervisor starts the next
   (^nactor-d120). The child's error type is what the incarnation ended with; the service
   reports it as the reason it gave up with. *)
type failure = [ `Spawn of spawn_error | `Exited of Ox_process.Child.exit ]

let reason_of_failure : failure -> reason = function
  | `Spawn error -> `Spawn error
  | `Exited exit -> `Schedule_exhausted exit

let rec reason_cause : failure Ox.Cause.t -> reason Ox.Cause.t = function
  | Ox.Cause.Fail failure -> Ox.Cause.Fail (reason_of_failure failure)
  | Ox.Cause.Die (exn, bt) -> Ox.Cause.Die (exn, bt)
  | Ox.Cause.Interrupt id -> Ox.Cause.Interrupt id
  | Ox.Cause.Finalizer cause -> Ox.Cause.Finalizer (reason_cause cause)
  | Ox.Cause.Suppressed { primary; finalizer } ->
      Ox.Cause.Suppressed
        { primary = reason_cause primary; finalizer = reason_cause finalizer }
  | Ox.Cause.Concurrent causes -> Ox.Cause.Concurrent (List.map reason_cause causes)

let rec has_defect = function
  | Ox.Cause.Die _ -> true
  | Ox.Cause.Finalizer cause -> has_defect cause
  | Ox.Cause.Suppressed { primary; finalizer } ->
      has_defect primary || has_defect finalizer
  | Ox.Cause.Concurrent causes -> List.exists has_defect causes
  | Ox.Cause.Fail _ | Ox.Cause.Interrupt _ -> false

(* The delay before restart number [n] (from 1): the configured schedule, stepped [n]
   times. It is the same exponential, capped schedule the process supervisor applied. *)
let restart_delay backoff ~now_ms n =
  let rec go driver i =
    match Ox.Schedule.step ~now_ms ~input:(Ox_process.Child.Exited 1) driver with
    | Ox.Schedule.Continue metadata, next ->
        if i >= n then Some metadata.delay else go next (i + 1)
    | Ox.Schedule.Done _, _ -> None
  in
  go (Ox.Schedule.start (schedule backoff)) 1

let create ~sw ?launch config (deps : 'clock deps) =
  let launch : 'clock launch =
    match launch with Some launch -> launch | None -> launch_pipe ~caps:deps.caps
  in
  let stop_signal, resolve_stop = Eio.Promise.create () in
  let give_up, resolve_give_up = Eio.Promise.create () in
  let finished, resolve_finished = Eio.Promise.create () in
  let state =
    {
      tails = Ox.Agent.create ~sw ~init:(fun () -> []) ();
      signals = Eio.Stream.create max_int;
      events = Eio.Stream.create 32;
      logger = deps.logger;
      phase = `Restarting;
      generation = 0;
      current = None;
      failure = None;
      headed = not config.headless;
      pending = None;
      pid = None;
      closed_before_start = None;
      spawns = 0;
      abandoned = None;
      stop_signal;
      resolve_stop;
      give_up;
      resolve_give_up;
      finished;
      resolve_finished;
    }
  in
  let push signal = Eio.Stream.add state.signals signal in
  let abandon cause = if state.abandoned = None then state.abandoned <- Some cause in
  let pause (ctx : failure Ox.Supervisor.context) delay =
    Eio.Fiber.first
      (fun () -> Eio.Time.sleep deps.clock (Ox.Duration.to_seconds_float delay))
      (fun () -> Eio.Promise.await ctx.stop_requested)
  in
  let start_generation (ctx : failure Ox.Supervisor.context) =
    match state.abandoned with
    | Some _ ->
        (* the launch failed for good; the service is being stopped, nothing more spawns *)
        ctx.ready ();
        Eio.Promise.await ctx.stop_requested;
        Ok ()
    | None -> (
        (if ctx.incarnation > 1 then
           let now_ms = int_of_float (Eio.Time.now deps.clock *. 1000.) in
           match restart_delay config.backoff ~now_ms (ctx.incarnation - 1) with
           | Some delay -> pause ctx delay
           | None -> ());
        if Eio.Promise.is_resolved ctx.stop_requested then Ok ()
        else
          let child_sw = Ox.Scope.switch ctx.scope in
          match launch ~sw:child_sw ~clock:deps.clock ~mgr:deps.mgr config with
          | exception (Eio.Cancel.Cancelled _ as ex) -> raise ex
          | exception ex ->
              let bt = Printexc.get_raw_backtrace () in
              abandon (Ox.Cause.Die (ex, bt));
              Printexc.raise_with_backtrace ex bt
          | Error error ->
              abandon (Ox.Cause.Fail (`Spawn error));
              Error (`Spawn error)
          | Ok (child, transport) -> (
              state.spawns <- state.spawns + 1;
              let generation = state.spawns in
              let cdp = Cdp.create ~sw:child_sw ~clock:deps.clock transport in
              let tail = Chrome_stderr.create () in
              let drained, resolve = Eio.Promise.create () in
              ignore
                (Ox.Agent.update state.tails ~fn:(fun tails ->
                     (generation, tail, drained) :: tails));
              (match Ox_process.Child.stderr child with
              | None -> Eio.Promise.resolve resolve ()
              | Some source ->
                  Eio.Fiber.fork ~sw:child_sw (fun () ->
                      Fun.protect
                        ~finally:(fun () -> Eio.Promise.resolve resolve ())
                        (fun () -> Chrome_stderr.read tail source)));
              state.pending <- Some cdp;
              state.pid <- Some (Ox_process.Child.pid child);
              Eio.Fiber.fork_daemon ~sw:child_sw (fun () ->
                  let _reason = Eio.Promise.await (Cdp.closed cdp) in
                  push (`Transport_closed generation);
                  (* The generation is over either way: a browser we cannot talk to still
                     holds the profile lock, so the process is retired before the restart. *)
                  ignore (Ox_process.Child.stop child);
                  `Stop_daemon);
              push (`Supervised (Ox_process.Supervised.Started generation));
              ctx.ready ();
              match
                Eio.Fiber.first
                  (fun () -> `Exited (Ox_process.Child.await child))
                  (fun () ->
                    Eio.Promise.await ctx.stop_requested;
                    `Stop)
              with
              | `Exited exit ->
                  (* An [Error] ends the child's scope by cancelling its fibers, so the
                     stderr reader is allowed to reach end of input first: the generation's
                     diagnostics are complete when it is reported lost. *)
                  Eio.Promise.await drained;
                  (* One turn between [Started] and an exit that follows at once: a reader
                     that has just taken [Started] still finds its connection, as it did
                     when the exit crossed the process supervisor's fibers. *)
                  Eio.Fiber.yield ();
                  push (`Supervised (Ox_process.Supervised.Exited (generation, exit)));
                  Error (`Exited exit)
              | `Stop -> Ok ()))
  in
  let pp_failure ppf = function
    | `Spawn error -> Format.fprintf ppf "spawn: %a" pp_reason (`Spawn error)
    | `Exited exit -> pp_reason ppf (`Schedule_exhausted exit)
  in
  let on_event = function
    | Ox.Supervisor.Child_exited { cause = Some cause; induced = false; _ } ->
        if has_defect cause then
          Log.lifecycle state.logger Ox_observability.Logger.Error
            ~msg:"chrome generation ended with a defect"
            [ Log.string "cause" (Format.asprintf "%a" (Ox.Cause.pp pp_failure) cause) ];
        if state.abandoned <> None && not (Eio.Promise.is_resolved state.give_up) then
          Eio.Promise.resolve state.resolve_give_up ()
    | _ -> ()
  in
  let intensity =
    {
      Ox.Supervisor.max_restarts = config.backoff.attempts;
      window = Ox.Duration.days 36500;
    }
  in
  let gave_up cause = push (`Supervised (Ox_process.Supervised.Gave_up cause)) in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      let run () =
        match
          Ox.Scope.supervised_error ~sw (fun scope ->
              match
                Ox.Supervisor.start ~scope ~clock:deps.clock ~intensity ~on_event
                  ~strategy:Ox.Supervisor.One_for_one
                  [
                    Ox.Supervisor.child ~id:"chrome" ~restart:Ox.Supervisor.Permanent
                      ~shutdown:Ox.Supervisor.Infinity start_generation;
                  ]
              with
              | Error (`Invalid_supervisor message) ->
                  invalid_arg ("Chrome.create: " ^ message)
              | Error (`Start_failed failure) ->
                  gave_up
                    (match state.abandoned with
                    | Some cause -> cause
                    | None -> reason_cause failure.Ox.Supervisor.cause);
                  Ok ()
              | Ok supervisor ->
                  Eio.Fiber.first
                    (fun () -> ignore (Ox.Supervisor.await supervisor))
                    (fun () ->
                      Eio.Fiber.first
                        (fun () -> Eio.Promise.await state.stop_signal)
                        (fun () ->
                          Eio.Promise.await state.give_up;
                          Option.iter gave_up state.abandoned);
                      ignore (Ox.Supervisor.stop supervisor));
                  Ok ())
        with
        | Ok () -> ()
        | Error (`Restart_intensity_exceeded exceeded) ->
            gave_up
              (match exceeded.Ox.Supervisor.last_cause with
              | Some cause -> reason_cause cause
              | None -> Ox.Cause.Fail (`Schedule_exhausted (Ox_process.Child.Exited 0)))
      in
      let result =
        match run () with
        | () -> Ok ()
        | exception Eio.Cancel.Cancelled _ -> Ok ()
        | exception ex ->
            let bt = Printexc.get_raw_backtrace () in
            gave_up (Ox.Cause.Die (ex, bt));
            Error ex
      in
      Eio.Cancel.protect (fun () ->
          push (`Supervised Ox_process.Supervised.Stopped);
          Eio.Promise.resolve state.resolve_finished ());
      match result with Ok () -> `Stop_daemon | Error ex -> raise ex);
  Eio.Fiber.fork_daemon ~sw (fun () -> observe state);
  { state }

let generation t = t.state.spawns

let status t =
  {
    generation = t.state.spawns;
    phase = t.state.phase;
    failure = t.state.failure;
    headed = t.state.headed;
    pid = (if t.state.phase = `Running then t.state.pid else None);
  }

let connection t =
  match (t.state.phase, t.state.current) with
  | `Running, Some (_, cdp) -> Ok cdp
  | _ -> Error `Browser_unavailable

let events t = t.state.events

let stop t =
  Eio.Cancel.protect (fun () ->
      if not (Eio.Promise.is_resolved t.state.stop_signal) then
        Eio.Promise.resolve t.state.resolve_stop ();
      Eio.Promise.await t.state.finished)
