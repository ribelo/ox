type restart = Permanent | Temporary | Transient
type shutdown = Brutal_kill | Timeout of Duration.t | Infinity
type strategy = One_for_one | One_for_all | Rest_for_one
type auto_shutdown = Never | Any_significant | All_significant
type intensity = { max_restarts : int; window : Duration.t }

type 'e context = {
  scope : 'e Scope.t;
  stop_requested : unit Eio.Promise.t;
  incarnation : int;
  ready : unit -> unit;
}

type 'e child = {
  id : string;
  restart : restart;
  shutdown : shutdown;
  significant : bool;
  start : 'e context -> (unit, 'e) result;
}

let default_shutdown = Timeout (Duration.seconds 5)

let child ~id ?(restart = Permanent) ?(shutdown = default_shutdown) ?(significant = false)
    start =
  { id; restart; shutdown; significant; start }

type ('input, 'e) template = {
  template_id : string;
  template_restart : restart;
  template_shutdown : shutdown;
  template_start : 'input -> 'e context -> (unit, 'e) result;
}

let template ~id ?(restart = Permanent) ?(shutdown = default_shutdown) start =
  {
    template_id = id;
    template_restart = restart;
    template_shutdown = shutdown;
    template_start = start;
  }

type 'e event =
  | Child_started of { child_id : string; incarnation : int }
  | Child_stop_requested of { child_id : string; incarnation : int; mode : shutdown }
  | Child_exited of {
      child_id : string;
      incarnation : int;
      cause : 'e Cause.t option;
      induced : bool;
    }
  | Restart_attempt of { child_id : string; attempt : int }
  | Shutting_down of [ `Requested | `Auto_shutdown | `Restart_intensity_exceeded ]

type 'e intensity_error = {
  child_id : string;
  max_restarts : int;
  window : Duration.t;
  last_cause : 'e Cause.t option;
}

type 'e start_failure = { failed_id : string; cause : 'e Cause.t }

type 'e outcome =
  | Stopped
  | Auto_shutdown
  | Cancelled
  | Intensity_exceeded of 'e intensity_error

(* One run of a child's start function. Every field is touched only by the supervisor's
   fiber and the incarnation's own fiber, which Eio never runs at the same instant. *)
type 'e incarnation = {
  number : int;
  ready : unit Eio.Promise.t;
  resolve_ready : unit Eio.Promise.u;
  mutable is_ready : bool;
  stop_signal : unit Eio.Promise.t;
  resolve_stop : unit Eio.Promise.u;
  mutable signalled : bool;
  finished : (unit, 'e) Exit.t Eio.Promise.t;
  resolve_finished : (unit, 'e) Exit.t Eio.Promise.u;
  mutable cancel : Eio.Cancel.t option;
  mutable cancel_requested : bool;
  mutable induced : bool; (* the supervisor asked it to stop *)
  mutable handled : bool; (* its exit was already classified *)
}

(* [Down] is "needs a start": never started, failed and awaiting its restart, or stopped as
   collateral of a group restart. [Done] completed and is not coming back. *)
type 'e phase = Live of 'e incarnation | Down | Done

type 'e entry = {
  spec_id : string;
  restart : restart;
  shutdown : shutdown;
  significant : bool;
  start : 'e context -> (unit, 'e) result;
  mutable phase : 'e phase;
  mutable count : int;
  mutable last_cause : 'e Cause.t option;
}

type 'e message =
  | Exited of 'e entry * 'e incarnation
  | Terminate of string * (unit, [ `Unknown_child | `Stopped ]) result Eio.Promise.u
  | Add of
      'e entry
      * (unit, [ `Start_failed of 'e start_failure | `Stopped ]) result Eio.Promise.u

type 'e t = {
  messages : 'e message Eio.Stream.t; (* unbounded: publishing never blocks *)
  stop_signal : unit Eio.Promise.t;
  resolve_stop : unit Eio.Promise.u;
  mutable stop_requested : bool;
  finished : 'e outcome Eio.Promise.t;
  resolve_finished : 'e outcome Eio.Promise.u;
  mutable closed : bool;
  mutable entries : 'e entry list;
}

type 'e config = {
  now : unit -> Mtime.t;
  with_deadline :
    Duration.t -> (unit -> (unit, [ `Timeout ]) result) -> (unit, [ `Timeout ]) result;
  intensity : intensity;
  auto : auto_shutdown;
  strategy : strategy;
  dynamic : bool;
  on_event : 'e event -> unit;
  interrupt : Interrupt_id.t;
}

let make_entry (spec : 'e child) =
  {
    spec_id = spec.id;
    restart = spec.restart;
    shutdown = spec.shutdown;
    significant = spec.significant;
    start = spec.start;
    phase = Down;
    count = 0;
    last_cause = None;
  }

let create_t () =
  let stop_signal, resolve_stop = Eio.Promise.create () in
  let finished, resolve_finished = Eio.Promise.create () in
  {
    messages = Eio.Stream.create max_int;
    stop_signal;
    resolve_stop;
    stop_requested = false;
    finished;
    resolve_finished;
    closed = false;
    entries = [];
  }

let request_stop t =
  if not t.stop_requested then (
    t.stop_requested <- true;
    Eio.Promise.resolve t.resolve_stop ())

let rec has_defect = function
  | Cause.Die _ | Cause.Finalizer _ -> true
  | Cause.Suppressed { primary; finalizer } -> has_defect primary || has_defect finalizer
  | Cause.Concurrent causes -> List.exists has_defect causes
  | Cause.Fail _ | Cause.Interrupt _ -> false

let rec defect_exns acc = function
  | Cause.Die (ex, bt) -> (ex, bt) :: acc
  | Cause.Finalizer cause -> defect_exns acc cause
  | Cause.Suppressed { primary; finalizer } ->
      defect_exns (defect_exns acc primary) finalizer
  | Cause.Concurrent causes -> List.fold_left defect_exns acc causes
  | Cause.Fail _ | Cause.Interrupt _ -> acc

let default_on_event = function
  | Child_exited { child_id; incarnation; cause = Some cause; induced } ->
      Eio.traceln "supervisor: child %s#%d exited%s: %a" child_id incarnation
        (if induced then " while stopping" else "")
        (Cause.pp (fun fmt _ -> Format.pp_print_string fmt "<typed failure>"))
        cause
  | _ -> ()

let raise_defects = function
  | [] -> ()
  | defects -> (
      let all = List.concat_map (fun cause -> List.rev (defect_exns [] cause)) defects in
      match all with
      | [] -> ()
      | [ (ex, bt) ] -> Printexc.raise_with_backtrace ex bt
      | many -> raise (Eio.Exn.Multiple many))

type 'e terminal =
  | Terminal_stop
  | Terminal_auto
  | Terminal_intensity of 'e intensity_error

(* The supervisor's fiber. Returns the terminal outcome after every child was joined; a
   cancellation of the caller propagates out of the switch, which cancels and awaits the
   children before the exception leaves. *)
let supervise (type e) (t : e t) (cfg : e config) ~(initial : e entry list)
    ~(started : (unit, e start_failure) result Eio.Promise.u) :
    (unit, e intensity_error) result =
  let defects : e Cause.t list ref = ref [] in
  let attempts : Mtime.t list ref = ref [] in
  let window_ms = Int64.of_int (Duration.to_ms cfg.intensity.window) in
  let emit event = cfg.on_event event in
  t.entries <- initial;
  let close_out outcome =
    t.closed <- true;
    Eio.Promise.resolve t.resolve_finished outcome;
    let rec drain () =
      match Eio.Stream.take_nonblocking t.messages with
      | None -> ()
      | Some (Exited _) -> drain ()
      | Some (Terminate (_, reply)) ->
          Eio.Promise.resolve reply (Error `Stopped);
          drain ()
      | Some (Add (_, reply)) ->
          Eio.Promise.resolve reply (Error `Stopped);
          drain ()
    in
    drain ()
  in
  let result =
    try
      Eio.Switch.run ~name:"supervisor" @@ fun group_sw ->
      let launch (entry : e entry) =
        entry.count <- entry.count + 1;
        let ready, resolve_ready = Eio.Promise.create () in
        let stop_signal, resolve_stop = Eio.Promise.create () in
        let finished, resolve_finished = Eio.Promise.create () in
        let inc =
          {
            number = entry.count;
            ready;
            resolve_ready;
            is_ready = false;
            stop_signal;
            resolve_stop;
            signalled = false;
            finished;
            resolve_finished;
            cancel = None;
            cancel_requested = false;
            induced = false;
            handled = false;
          }
        in
        entry.phase <- Live inc;
        let mark_ready () =
          if not inc.is_ready then (
            inc.is_ready <- true;
            Eio.Promise.resolve inc.resolve_ready ())
        in
        Eio.Fiber.fork ~sw:group_sw (fun () ->
            let exit =
              Eio.Cancel.sub (fun cc ->
                  inc.cancel <- Some cc;
                  if inc.cancel_requested then
                    Eio.Cancel.cancel cc (Interrupt_id.stop cfg.interrupt);
                  Scope.run (fun sw ->
                      Scope.supervised_error ~sw (fun scope ->
                          entry.start
                            {
                              scope;
                              stop_requested = inc.stop_signal;
                              incarnation = inc.number;
                              ready = mark_ready;
                            })))
            in
            Eio.Promise.resolve inc.resolve_finished exit;
            Eio.Stream.add t.messages (Exited (entry, inc)));
        inc
      in
      let signal_stop inc =
        if not inc.signalled then (
          inc.signalled <- true;
          Eio.Promise.resolve inc.resolve_stop ())
      in
      let cancel_incarnation inc =
        inc.cancel_requested <- true;
        Option.iter
          (fun cc -> Eio.Cancel.cancel cc (Interrupt_id.stop cfg.interrupt))
          inc.cancel
      in
      let cause_of = function Exit.Success () -> None | Exit.Failure c -> Some c in
      (* An exit nobody asked for: classify it, decide whether the child comes back. *)
      let settle_spontaneous (entry : e entry) inc =
        inc.handled <- true;
        let cause = cause_of (Eio.Promise.await inc.finished) in
        emit
          (Child_exited
             {
               child_id = entry.spec_id;
               incarnation = inc.number;
               cause;
               induced = false;
             });
        entry.last_cause <- cause;
        let eligible =
          match entry.restart with
          | Permanent -> true
          | Temporary -> false
          | Transient -> cause <> None
        in
        if eligible then entry.phase <- Down
        else (
          entry.phase <- Done;
          (* a dynamic instance that will not come back leaves the list *)
          if cfg.dynamic then t.entries <- List.filter (fun e -> e != entry) t.entries)
      in
      (* The exit of an incarnation the supervisor stopped: not a failure event, but a
         cleanup defect is kept for the terminal outcome. *)
      let settle_induced (entry : e entry) inc =
        inc.handled <- true;
        let cause = cause_of (Eio.Promise.await inc.finished) in
        emit
          (Child_exited
             { child_id = entry.spec_id; incarnation = inc.number; cause; induced = true });
        match cause with Some c when has_defect c -> defects := c :: !defects | _ -> ()
      in
      let stop_entry (entry : e entry) =
        match entry.phase with
        | Down | Done -> ()
        | Live inc ->
            inc.induced <- true;
            emit
              (Child_stop_requested
                 {
                   child_id = entry.spec_id;
                   incarnation = inc.number;
                   mode = entry.shutdown;
                 });
            (match entry.shutdown with
            | Brutal_kill -> cancel_incarnation inc
            | Infinity -> signal_stop inc
            | Timeout limit -> (
                signal_stop inc;
                match
                  cfg.with_deadline limit (fun () ->
                      ignore (Eio.Promise.await inc.finished);
                      Ok ())
                with
                | Ok () -> ()
                | Error `Timeout -> cancel_incarnation inc));
            ignore (Eio.Promise.await inc.finished);
            settle_induced entry inc
      in
      (* Classify every exit that is already complete and unclaimed, so simultaneous exits
         are one recovery. *)
      let sweep () =
        List.iter
          (fun (entry : e entry) ->
            match entry.phase with
            | Live inc
              when (not inc.handled) && (not inc.induced)
                   && Eio.Promise.is_resolved inc.finished ->
                settle_spontaneous entry inc
            | _ -> ())
          t.entries
      in
      let remove entry = t.entries <- List.filter (fun e -> e != entry) t.entries in
      let is_down (entry : e entry) =
        match entry.phase with Down -> true | _ -> false
      in
      let auto_due () =
        let significant = List.filter (fun (e : e entry) -> e.significant) t.entries in
        let finished (e : e entry) = match e.phase with Done -> true | _ -> false in
        match cfg.auto with
        | Never -> false
        | Any_significant -> List.exists finished significant
        | All_significant -> significant <> [] && List.for_all finished significant
      in
      let index_of entry =
        let rec go i = function
          | [] -> max_int
          | e :: rest -> if e == entry then i else go (i + 1) rest
        in
        go 0 t.entries
      in
      let wait_ready inc =
        let outcome =
          Eio.Fiber.first
            (fun () ->
              Eio.Promise.await inc.ready;
              `Ready)
            (fun () ->
              Eio.Fiber.first
                (fun () ->
                  ignore (Eio.Promise.await inc.finished);
                  `Finished)
                (fun () ->
                  Eio.Promise.await t.stop_signal;
                  `Stop))
        in
        match outcome with
        | `Ready -> `Ready
        | `Stop -> `Stop
        | `Finished -> (
            if inc.is_ready then `Ready
            else
              match Eio.Promise.await inc.finished with
              | Exit.Success () -> `Ready (* completed normally: it started fine *)
              | Exit.Failure _ -> `Failed_start)
      in
      (* Start every [Down] child in specification order, each once the previous is
         ready. A failure to become ready that needs another recovery stops the batch. *)
      let start_downs ~initial =
        let rec go = function
          | [] -> `Started
          | (entry : e entry) :: rest when not (is_down entry) -> go rest
          | entry :: rest -> (
              if t.stop_requested then `Stop
              else
                let inc = launch entry in
                match wait_ready inc with
                | `Ready ->
                    emit
                      (Child_started
                         { child_id = entry.spec_id; incarnation = inc.number });
                    go rest
                | `Stop -> `Stop
                | `Failed_start ->
                    settle_spontaneous entry inc;
                    if initial then
                      `Initial_failed (entry.spec_id, Option.get entry.last_cause)
                    else if is_down entry then `Failed entry
                    else go rest)
        in
        go t.entries
      in
      let check_intensity (entry : e entry) =
        let now = cfg.now () in
        (* ^safe-p9cw ^safe-5a9k: compare exact native elapsed spans to the
           millisecond window; the boundary remains exclusive. Dividing first
           also avoids overflowing when a valid Duration is a very large window. *)
        attempts :=
          List.filter
            (fun at ->
              let ns = Mtime.Span.to_uint64_ns (Mtime.span at now) in
              Int64.unsigned_compare (Int64.unsigned_div ns 1_000_000L) window_ms < 0)
            !attempts;
        if List.length !attempts >= cfg.intensity.max_restarts then
          Error
            {
              child_id = entry.spec_id;
              max_restarts = cfg.intensity.max_restarts;
              window = cfg.intensity.window;
              last_cause = entry.last_cause;
            }
        else (
          attempts := now :: !attempts;
          emit
            (Restart_attempt { child_id = entry.spec_id; attempt = List.length !attempts });
          Ok ())
      in
      (* Stop the active collateral of the first failed child, in reverse specification
         order, then restart what is [Down] in specification order. *)
      let rec recover () =
        match List.find_opt is_down t.entries with
        | None -> `Recovered
        | Some anchor -> (
            match check_intensity anchor with
            | Error error -> `Exceeded error
            | Ok () -> (
                let anchor_index = index_of anchor in
                let collateral =
                  List.filteri
                    (fun i (entry : e entry) ->
                      match (cfg.strategy, entry.phase) with
                      | One_for_one, _ -> false
                      | One_for_all, Live _ -> true
                      | Rest_for_one, Live _ -> i > anchor_index
                      | _, (Down | Done) -> false)
                    t.entries
                in
                List.iter
                  (fun (entry : e entry) ->
                    stop_entry entry;
                    match entry.restart with
                    | Temporary -> remove entry
                    | Permanent | Transient -> entry.phase <- Down)
                  (List.rev collateral);
                match start_downs ~initial:false with
                | `Started -> `Recovered
                | `Stop -> `Stop
                | `Initial_failed _ -> assert false
                | `Failed _ -> recover ()))
      in
      let shutdown_all () =
        sweep ();
        List.iter stop_entry (List.rev t.entries)
      in
      let rec loop () =
        if t.stop_requested then Terminal_stop
        else
          let next =
            Eio.Fiber.first
              (fun () ->
                Eio.Promise.await t.stop_signal;
                `Stop)
              (fun () -> `Message (Eio.Stream.take t.messages))
          in
          match next with
          | `Stop -> Terminal_stop
          | `Message message -> (
              match handle message with None -> loop () | Some terminal -> terminal)
      and react () =
        if auto_due () then Some Terminal_auto
        else
          match recover () with
          | `Recovered -> None
          | `Stop -> Some Terminal_stop
          | `Exceeded error -> Some (Terminal_intensity error)
      and handle = function
        | Exited (entry, inc) -> (
            match entry.phase with
            | Live current when current == inc && not inc.handled ->
                sweep ();
                react ()
            | _ -> None (* stale: an earlier incarnation, or already claimed *))
        | Terminate (id, reply) -> (
            match List.find_opt (fun (e : e entry) -> e.spec_id = id) t.entries with
            | None ->
                Eio.Promise.resolve reply (Error `Unknown_child);
                None
            | Some entry ->
                stop_entry entry;
                remove entry;
                Eio.Promise.resolve reply (Ok ());
                if auto_due () then Some Terminal_auto else None)
        | Add (entry, reply) -> (
            t.entries <- t.entries @ [ entry ];
            let inc = launch entry in
            match wait_ready inc with
            | `Ready ->
                emit
                  (Child_started { child_id = entry.spec_id; incarnation = inc.number });
                Eio.Promise.resolve reply (Ok ());
                None
            | `Stop ->
                Eio.Promise.resolve reply (Error `Stopped);
                Some Terminal_stop
            | `Failed_start ->
                settle_spontaneous entry inc;
                remove entry;
                Eio.Promise.resolve reply
                  (Error
                     (`Start_failed
                        { failed_id = entry.spec_id; cause = Option.get entry.last_cause }));
                None)
      in
      let terminal =
        match start_downs ~initial:true with
        | `Started ->
            Eio.Promise.resolve started (Ok ());
            loop ()
        | `Stop ->
            Eio.Promise.resolve started (Ok ());
            Terminal_stop
        | `Initial_failed (failed_id, cause) ->
            shutdown_all ();
            Eio.Promise.resolve started (Error { failed_id; cause });
            Terminal_stop
        | `Failed _ -> assert false
      in
      emit
        (Shutting_down
           (match terminal with
           | Terminal_stop -> `Requested
           | Terminal_auto -> `Auto_shutdown
           | Terminal_intensity _ -> `Restart_intensity_exceeded));
      shutdown_all ();
      terminal
    with exception_ ->
      let bt = Printexc.get_raw_backtrace () in
      close_out Cancelled;
      Printexc.raise_with_backtrace exception_ bt
  in
  let outcome, result =
    match result with
    | Terminal_stop -> (Stopped, Ok ())
    | Terminal_auto -> (Auto_shutdown, Ok ())
    | Terminal_intensity error -> (Intensity_exceeded error, Error error)
  in
  close_out outcome;
  raise_defects !defects;
  result

let same_id_twice ids =
  let sorted = List.sort String.compare ids in
  let rec go = function a :: (b :: _ as rest) -> a = b || go rest | _ -> false in
  go sorted

let validate_intensity (intensity : intensity) =
  if intensity.max_restarts < 0 then Error "max_restarts must not be negative"
  else if Duration.is_zero intensity.window then
    Error "the intensity window must be positive"
  else Ok ()

let validate ~intensity children =
  match validate_intensity intensity with
  | Error _ as e -> e
  | Ok () ->
      if List.exists (fun (c : _ child) -> c.id = "") children then
        Error "a child id must not be empty"
      else if same_id_twice (List.map (fun (c : _ child) -> c.id) children) then
        Error "child ids must be unique"
      else if
        List.exists (fun (c : _ child) -> c.significant && c.restart = Permanent) children
      then Error "a Permanent child cannot be significant"
      else Ok ()

let config ~clock ~intensity ~auto ~strategy ~dynamic ~on_event =
  {
    now = (fun () -> Eio.Time.Mono.now clock);
    with_deadline = (fun limit f -> Timeout.timeout_mono ~clock limit f);
    intensity;
    auto;
    strategy;
    dynamic;
    on_event = Option.value on_event ~default:default_on_event;
    interrupt = Interrupt_id.create ();
  }

let launch_supervisor ~scope ~cfg ~initial =
  Eio.Switch.check (Scope.switch scope);
  let t = create_t () in
  let started, resolve_started = Eio.Promise.create () in
  Scope.fork_error_daemon scope (fun () ->
      match supervise t cfg ~initial ~started:resolve_started with
      | Ok () -> Ok ()
      | Error error -> Error (`Restart_intensity_exceeded error));
  (t, started)

let start ~scope ~clock ~intensity ?(auto_shutdown = Never) ?on_event ~strategy children =
  match validate ~intensity children with
  | Error message -> Error (`Invalid_supervisor message)
  | Ok () -> (
      let cfg =
        config ~clock ~intensity ~auto:auto_shutdown ~strategy ~dynamic:false ~on_event
      in
      let t, started =
        launch_supervisor ~scope ~cfg ~initial:(List.map make_entry children)
      in
      match Eio.Promise.await started with
      | Ok () -> Ok t
      | Error failure -> Error (`Start_failed failure))

let stop t =
  request_stop t;
  Eio.Promise.await t.finished

let await t = Eio.Promise.await t.finished

type child_state = [ `Starting | `Running | `Restarting | `Completed ]
type child_info = { id : string; incarnation : int; state : child_state }

let children t =
  List.map
    (fun (entry : _ entry) ->
      let state : child_state =
        match entry.phase with
        | Live inc -> if inc.is_ready then `Running else `Starting
        | Down -> `Restarting
        | Done -> `Completed
      in
      { id = entry.spec_id; incarnation = entry.count; state })
    t.entries

let terminate_child t id =
  let promise, resolve = Eio.Promise.create () in
  if t.closed then Error `Stopped
  else (
    Eio.Stream.add t.messages (Terminate (id, resolve));
    match Eio.Promise.await promise with
    | Ok () -> Ok ()
    | Error `Unknown_child -> Error `Unknown_child
    | Error `Stopped -> Error `Stopped)

type ('input, 'e) simple = {
  sup : 'e t;
  template : ('input, 'e) template;
  mutable next : int;
}

let start_simple ~scope ~clock ~intensity ?on_event template =
  match validate_intensity intensity with
  | Error message -> Error (`Invalid_supervisor message)
  | Ok () -> (
      let cfg =
        config ~clock ~intensity ~auto:Never ~strategy:One_for_one ~dynamic:true ~on_event
      in
      let sup, started = launch_supervisor ~scope ~cfg ~initial:[] in
      match Eio.Promise.await started with
      | Ok () -> Ok { sup; template; next = 0 }
      | Error _ -> assert false)

let start_child simple input =
  let t = simple.sup in
  if t.closed then Error `Stopped
  else (
    simple.next <- simple.next + 1;
    let id = Printf.sprintf "%s#%d" simple.template.template_id simple.next in
    let entry =
      {
        spec_id = id;
        restart = simple.template.template_restart;
        shutdown = simple.template.template_shutdown;
        significant = false;
        start = (fun context -> simple.template.template_start input context);
        phase = Down;
        count = 0;
        last_cause = None;
      }
    in
    let promise, resolve = Eio.Promise.create () in
    Eio.Stream.add t.messages (Add (entry, resolve));
    match Eio.Promise.await promise with
    | Ok () -> Ok id
    | Error (`Start_failed _ as e) -> Error e
    | Error `Stopped -> Error `Stopped)

let supervisor simple = simple.sup
