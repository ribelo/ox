(* Row 47, story 13: Supervisor. Every case cites nactor-d120 (and nactor-75ef where an Agent
   is involved). Children are scripted, time is Eio_mock's clock, and ordering is forced with
   promises: nothing here sleeps on the wall clock. The shared [log] records what the
   supervisor reports (its events) and what the scripted children do, in one order. *)
open Ox
module S = Supervisor

let check_bool = Alcotest.(check bool)
let check_int = Alcotest.(check int)
let check_strings = Alcotest.(check (list string))
let fmt = Printf.sprintf

exception Boom of string

let run f = Eio_mock.Backend.run_full (fun env -> f env#clock)

let quiesce () =
  for _ = 1 to 60 do
    Eio.Fiber.yield ()
  done

(* The owning scope: a supervised scope whose typed error type admits the supervisor's. *)
let scoped f = Eio.Switch.run (fun sw -> Scope.supervised_error ~sw f)

let rec has_die = function
  | Cause.Die _ -> true
  | Cause.Finalizer c -> has_die c
  | Cause.Suppressed { primary; finalizer } -> has_die primary || has_die finalizer
  | Cause.Concurrent cs -> List.exists has_die cs
  | Cause.Fail _ | Cause.Interrupt _ -> false

let rec has_boom name = function
  | Cause.Die (Boom n, _) -> n = name
  | Cause.Finalizer c -> has_boom name c
  | Cause.Suppressed { primary; finalizer } ->
      has_boom name primary || has_boom name finalizer
  | Cause.Concurrent cs -> List.exists (has_boom name) cs
  | _ -> false

let exceeded = function
  | Error (`Restart_intensity_exceeded (e : string S.intensity_error)) -> e
  | Ok () -> Alcotest.fail "expected the restart intensity to be exceeded"

let make_log () =
  let entries = ref [] in
  ((fun line -> entries := line :: !entries), fun () -> List.rev !entries)

let rec cause_tag = function
  | Cause.Fail _ -> "fail"
  | Cause.Die _ -> "die"
  | Cause.Interrupt _ -> "interrupt"
  | Cause.Finalizer c -> "cleanup:" ^ cause_tag c
  | Cause.Suppressed { primary; finalizer } ->
      cause_tag primary ^ "+" ^ cause_tag finalizer
  | Cause.Concurrent _ -> "many"

let describe : _ S.event -> string = function
  | S.Child_started { child_id; incarnation } -> fmt "up %s#%d" child_id incarnation
  | S.Child_stop_requested { child_id; incarnation; _ } ->
      fmt "stop %s#%d" child_id incarnation
  | S.Child_exited { child_id; incarnation; cause; induced } ->
      fmt "exit %s#%d %s%s" child_id incarnation
        (match cause with None -> "normal" | Some c -> cause_tag c)
        (if induced then " induced" else "")
  | S.Restart_attempt { child_id; attempt } -> fmt "attempt %s %d" child_id attempt
  | S.Shutting_down `Requested -> "shutting-down requested"
  | S.Shutting_down `Auto_shutdown -> "shutting-down auto"
  | S.Shutting_down `Restart_intensity_exceeded -> "shutting-down intensity"

let index log line =
  let rec go i = function
    | [] -> Alcotest.failf "%S not in the log: [%s]" line (String.concat "; " log)
    | x :: rest -> if x = line then i else go (i + 1) rest
  in
  go 0 log

let mem log line = List.mem line log
let before log a b = index log a < index log b

(* What a scripted incarnation does once it is up. *)
type act =
  | Serve (* until asked to stop, then end normally *)
  | Complete
  | Fail of string
  | Crash of exn
  | Early_fail of string (* fail before [ready] *)
  | On of unit Eio.Promise.t * act (* wait for the trigger (or a stop), then act *)
  | Ignore_stop (* never looks at the stop signal; only cancellation ends it *)

let rec act ~log id (ctx : string S.context) = function
  | Serve ->
      Eio.Promise.await ctx.stop_requested;
      log (fmt "graceful %s#%d" id ctx.incarnation);
      Ok ()
  | Complete -> Ok ()
  | Fail e -> Error e
  | Crash ex -> raise ex
  | Early_fail e -> Error e
  | Ignore_stop -> Eio.Fiber.await_cancel ()
  | On (trigger, next) -> (
      match
        Eio.Fiber.first
          (fun () ->
            Eio.Promise.await trigger;
            `Go)
          (fun () ->
            Eio.Promise.await ctx.stop_requested;
            `Stop)
      with
      | `Go -> act ~log id ctx next
      | `Stop ->
          log (fmt "graceful %s#%d" id ctx.incarnation);
          Ok ())

let scripted ~log ?restart ?shutdown ?significant id (script : int -> act) =
  S.child ~id ?restart ?shutdown ?significant (fun ctx ->
      log (fmt "start %s#%d" id ctx.incarnation);
      Eio.Switch.on_release (Scope.switch ctx.scope) (fun () ->
          log (fmt "released %s#%d" id ctx.incarnation));
      match script ctx.incarnation with
      | Early_fail e -> Error e
      | a ->
          ctx.ready ();
          act ~log id ctx a)

let intensity ?(max_restarts = 100) ?(window = Duration.minutes 1) () : S.intensity =
  { max_restarts; window }

let trigger () = Eio.Promise.create ()
let fire (_, resolve) = Eio.Promise.resolve resolve ()
let promise (p, _) = p

let states sup =
  List.map (fun (i : S.child_info) -> (i.id, i.incarnation)) (S.children sup)

let start_ok ~scope ~clock ~log ?(intensity = intensity ()) ?auto_shutdown ~strategy
    children =
  match
    S.start ~scope ~clock ~intensity ?auto_shutdown
      ~on_event:(fun e -> log (describe e))
      ~strategy children
  with
  | Ok sup -> sup
  | Error (`Invalid_supervisor m) -> Alcotest.failf "invalid: %s" m
  | Error (`Start_failed f) -> Alcotest.failf "start failed: %s" f.S.failed_id

(* ---- strategies x restart types x outcomes ------------------------------------------- *)

type outcome = Normal | Typed | Defect

let outcome_name = function
  | Normal -> "normal"
  | Typed -> "typed failure"
  | Defect -> "defect"

let restart_name = function
  | S.Permanent -> "Permanent"
  | S.Temporary -> "Temporary"
  | S.Transient -> "Transient"

let strategy_name = function
  | S.One_for_one -> "One_for_one"
  | S.One_for_all -> "One_for_all"
  | S.Rest_for_one -> "Rest_for_one"

let eligible restart outcome =
  match (restart, outcome) with
  | S.Permanent, _ -> true
  | S.Temporary, _ -> false
  | S.Transient, Normal -> false
  | S.Transient, (Typed | Defect) -> true

(* Specification order: a Permanent, the subject b, a Transient, a Temporary. *)
let table_case strategy restart outcome =
  let name =
    fmt "%s / %s b exits with %s" (strategy_name strategy) (restart_name restart)
      (outcome_name outcome)
  in
  run (fun clock ->
      let log, get = make_log () in
      let trig = trigger () in
      let boom = Boom "b" in
      let b_exit =
        match outcome with Normal -> Complete | Typed -> Fail "b" | Defect -> Crash boom
      in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log ~strategy
                [
                  scripted ~log ~restart:S.Permanent "a" (fun _ -> Serve);
                  scripted ~log ~restart "b" (fun n ->
                      if n = 1 then On (promise trig, b_exit) else Serve);
                  scripted ~log ~restart:S.Transient "c" (fun _ -> Serve);
                  scripted ~log ~restart:S.Temporary "d" (fun _ -> Serve);
                ]
            in
            check_strings
              (name ^ ": specification order")
              [ "a"; "b"; "c"; "d" ]
              (List.map (fun (i : S.child_info) -> i.id) (S.children sup));
            fire trig;
            quiesce ();
            let counts = states sup in
            let count id = List.assoc_opt id counts in
            let l = get () in
            let expect_counts, gone =
              if not (eligible restart outcome) then
                ([ ("a", 1); ("b", 1); ("c", 1); ("d", 1) ], [])
              else
                match strategy with
                | S.One_for_one -> ([ ("a", 1); ("b", 2); ("c", 1); ("d", 1) ], [])
                | S.One_for_all -> ([ ("a", 2); ("b", 2); ("c", 2) ], [ "d" ])
                | S.Rest_for_one -> ([ ("a", 1); ("b", 2); ("c", 2) ], [ "d" ])
            in
            List.iter
              (fun (id, n) ->
                Alcotest.(check (option int))
                  (fmt "%s: %s incarnation" name id)
                  (Some n) (count id))
              expect_counts;
            List.iter
              (fun id -> check_bool (fmt "%s: %s removed" name id) true (count id = None))
              gone;
            let tag =
              match outcome with Normal -> "normal" | Typed -> "fail" | Defect -> "die"
            in
            check_bool
              (name ^ ": the exit is reported once, not induced")
              true
              (mem l (fmt "exit b#1 %s" tag));
            if not (eligible restart outcome) then (
              check_bool
                (name ^ ": an ineligible exit touches no sibling")
                false
                (List.exists
                   (fun line ->
                     String.length line >= 4
                     && (String.sub line 0 4 = "stop"
                        || (String.sub line 0 4 = "rele" && line <> "released b#1")))
                   l);
              check_bool (name ^ ": no recovery") false (List.mem "attempt b 1" l))
            else (
              check_bool (name ^ ": one recovery batch") true (mem l "attempt b 1");
              check_bool (name ^ ": no second batch") false (mem l "attempt b 2");
              match strategy with
              | S.One_for_one ->
                  check_bool (name ^ ": nobody is stopped") false (mem l "stop a#1");
                  check_bool
                    (name ^ ": b restarts after its release")
                    true
                    (before l "released b#1" "start b#2")
              | S.One_for_all ->
                  check_bool
                    (name ^ ": reverse stop order")
                    true
                    (before l "stop d#1" "stop c#1" && before l "stop c#1" "stop a#1");
                  List.iter
                    (fun id ->
                      check_bool
                        (fmt "%s: %s#1 fully released before any restart" name id)
                        true
                        (before l (fmt "released %s#1" id) "start a#2"))
                    [ "a"; "c"; "d"; "b" ];
                  check_bool
                    (name ^ ": forward restart order")
                    true
                    (before l "start a#2" "start b#2" && before l "start b#2" "start c#2");
                  check_bool
                    (name ^ ": a Temporary collateral is not restarted")
                    false (mem l "start d#2")
              | S.Rest_for_one ->
                  check_bool
                    (name ^ ": earlier sibling untouched")
                    false (mem l "stop a#1");
                  check_bool
                    (name ^ ": reverse stop order")
                    true
                    (before l "stop d#1" "stop c#1");
                  check_bool
                    (name ^ ": c fully released before it restarts")
                    true
                    (before l "released c#1" "start c#2");
                  check_bool
                    (name ^ ": forward restart order")
                    true
                    (before l "start b#2" "start c#2");
                  check_bool
                    (name ^ ": a Temporary collateral is not restarted")
                    false (mem l "start d#2"));
            ignore (S.stop sup);
            Ok ())
      in
      check_bool (name ^ ": the owning scope was not failed") true (result = Ok ()))

let strategy_table () =
  List.iter
    (fun strategy ->
      List.iter
        (fun restart -> List.iter (table_case strategy restart) [ Normal; Typed; Defect ])
        [ S.Permanent; S.Temporary; S.Transient ])
    [ S.One_for_one; S.One_for_all; S.Rest_for_one ]

(* ---- classification: defects, cleanup failures, cancellation identity ------------------- *)

let defect_reporting () =
  run (fun clock ->
      let log, get = make_log () in
      let seen = ref [] in
      let boom = Boom "child" in
      let result =
        scoped (fun scope ->
            let sup =
              match
                S.start ~scope ~clock
                  ~intensity:(intensity ~max_restarts:0 ())
                  ~on_event:(fun e ->
                    (match e with
                    | S.Child_exited { cause = Some c; _ } -> seen := c :: !seen
                    | _ -> ());
                    log (describe e))
                  ~strategy:S.One_for_one
                  [ scripted ~log "x" (fun _ -> Crash boom) ]
              with
              | Ok sup -> sup
              | Error _ -> Alcotest.fail "start"
            in
            ignore (S.await sup);
            Ok ())
      in
      let e = exceeded result in
      (match e.S.last_cause with
      | Some (Cause.Die (ex, _)) ->
          check_bool "the intensity error keeps the original exception" true (ex == boom)
      | _ -> Alcotest.fail "last_cause must be the defect");
      (match !seen with
      | [ Cause.Die (ex, _) ] ->
          check_bool "the exit event carries the original exception" true (ex == boom)
      | _ -> Alcotest.fail "the defect is reported exactly once");
      check_bool "a defect is an abnormal exit, logged" true (mem (get ()) "exit x#1 die");
      (* without a supervisor the same exception is a plain defect, unchanged *)
      let exit =
        Scope.run (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                Scope.fork scope (fun () -> raise boom);
                Eio.Fiber.await_cancel ()))
      in
      check_bool "outside a Supervisor the defect propagates unchanged" true
        (match exit with Exit.Failure (Cause.Die (ex, _)) -> ex == boom | _ -> false))

let cleanup_failures () =
  run (fun clock ->
      (* a cleanup defect during a requested stop is raised, never discarded *)
      let log, _ = make_log () in
      let exit =
        Scope.run (fun sw ->
            Scope.supervised_error ~sw (fun scope ->
                let sup =
                  start_ok ~scope ~clock ~log ~strategy:S.One_for_one
                    [
                      S.child ~id:"f" (fun ctx ->
                          Eio.Switch.on_release (Scope.switch ctx.scope) (fun () ->
                              raise (Boom "cleanup"));
                          ctx.ready ();
                          Eio.Promise.await ctx.stop_requested;
                          Ok ());
                    ]
                in
                ignore (S.stop sup);
                Ok ()))
      in
      (match exit with
      | Exit.Failure cause ->
          check_bool "the cleanup defect is in the scope's Cause" true
            (has_boom "cleanup" cause)
      | Exit.Success () -> Alcotest.fail "a cleanup defect during a stop was discarded");
      (* a spontaneous failure keeps its cleanup failure in the full Cause *)
      let log, _ = make_log () in
      let result =
        scoped (fun scope ->
            let sup =
              match
                S.start ~scope ~clock
                  ~intensity:(intensity ~max_restarts:0 ())
                  ~on_event:(fun e -> log (describe e))
                  ~strategy:S.One_for_one
                  [
                    S.child ~id:"g" (fun ctx ->
                        Eio.Switch.on_release (Scope.switch ctx.scope) (fun () ->
                            raise (Boom "late cleanup"));
                        ctx.ready ();
                        Error "body");
                  ]
              with
              | Ok sup -> sup
              | Error _ -> Alcotest.fail "start"
            in
            ignore (S.await sup);
            Ok ())
      in
      match (exceeded result).S.last_cause with
      | Some cause ->
          (* Scope.supervised_error's rule: a defect in the scope wins over a typed failure
             of its body, so the cleanup defect is what the Cause holds *)
          check_bool "the cleanup defect is in the child's Cause, not discarded" true
            (has_boom "late cleanup" cause)
      | None -> Alcotest.fail "last_cause")

let external_cancellation () =
  run (fun clock ->
      let log, get = make_log () in
      let id = Interrupt_id.create () in
      let cc = ref None and exit = ref None in
      Eio.Switch.run (fun outer ->
          Eio.Fiber.fork ~sw:outer (fun () ->
              exit :=
                Some
                  (Eio.Cancel.sub (fun c ->
                       cc := Some c;
                       Scope.run (fun sw ->
                           Scope.supervised_error ~sw (fun scope ->
                               ignore
                                 (start_ok ~scope ~clock ~log ~strategy:S.One_for_all
                                    [
                                      scripted ~log "a" (fun _ -> Serve);
                                      scripted ~log "b" (fun _ -> Serve);
                                    ]);
                               Eio.Fiber.await_cancel ())))));
          quiesce ();
          Eio.Cancel.cancel (Option.get !cc) (Interrupt_id.stop id);
          quiesce ());
      (match !exit with
      | Some (Exit.Failure (Cause.Interrupt (Some seen))) ->
          check_bool "the cancellation keeps its identity" true
            (Interrupt_id.equal seen id)
      | _ -> Alcotest.fail "external cancellation must surface as that Interrupt");
      let l = get () in
      check_bool "both children were cancelled and joined" true
        (mem l "released a#1" && mem l "released b#1");
      check_bool "never a recovery" false
        (List.exists (fun x -> String.length x > 7 && String.sub x 0 7 = "attempt") l);
      check_bool "never restarted" false (mem l "start a#2" || mem l "start b#2");
      check_bool "no graceful signal: parent cancellation takes precedence" false
        (mem l "graceful a#1"))

(* ---- restart intensity ----------------------------------------------------------------- *)

let crash_loop ~log ~clock ?(strategy = S.One_for_one) ~max_restarts
    ?(window = Duration.minutes 1) script =
  scoped (fun scope ->
      ignore
        (start_ok ~scope ~clock ~log
           ~intensity:(intensity ~max_restarts ~window ())
           ~strategy
           [ scripted ~log "x" script ]);
      Eio.Fiber.await_cancel ())

let starts_of l id =
  List.length
    (List.filter
       (fun x ->
         String.length x > 6
         && String.sub x 0 6 = "start "
         && String.sub x 6 (String.length x - 6 - 2) = id)
       l)

let intensity_budget () =
  run (fun clock ->
      (* exactly the allowed budget, then the next attempt ends the supervisor *)
      let log, get = make_log () in
      let e = exceeded (crash_loop ~log ~clock ~max_restarts:2 (fun _ -> Fail "x")) in
      let l = get () in
      check_int "one initial start plus exactly max_restarts restarts, no extra start" 3
        (starts_of l "x");
      Alcotest.(check string) "the child" "x" e.S.child_id;
      check_int "the budget" 2 e.S.max_restarts;
      check_bool "the last cause is the child's typed failure" true
        (match e.S.last_cause with Some (Cause.Fail "x") -> true | _ -> false);
      check_bool "the last incarnation was released" true (mem l "released x#3");
      (* zero disables automatic restart *)
      let log, get = make_log () in
      let e = exceeded (crash_loop ~log ~clock ~max_restarts:0 (fun _ -> Fail "z")) in
      check_int "zero restarts" 1 (starts_of (get ()) "x");
      check_int "max_restarts is reported" 0 e.S.max_restarts;
      check_bool "released before the error" true (mem (get ()) "released x#1");
      (* a Permanent child that keeps completing normally also exhausts it *)
      let log, _ = make_log () in
      let e = exceeded (crash_loop ~log ~clock ~max_restarts:1 (fun _ -> Complete)) in
      check_bool "normal completion leaves no last cause" true (e.S.last_cause = None))

let window_case ~gap ~expect_exceeded =
  run (fun clock ->
      let log, _ = make_log () in
      let t1 = trigger () and t2 = trigger () in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log
                ~intensity:(intensity ~max_restarts:1 ~window:(Duration.seconds 10) ())
                ~strategy:S.One_for_one
                [
                  scripted ~log "x" (function
                    | 1 -> On (promise t1, Fail "one")
                    | 2 -> On (promise t2, Fail "two")
                    | _ -> Serve);
                ]
            in
            fire t1;
            quiesce ();
            Eio.Time.sleep clock gap;
            fire t2;
            quiesce ();
            if not expect_exceeded then (
              check_bool "the third incarnation runs" true
                (List.assoc_opt "x" (states sup) = Some 3);
              ignore (S.stop sup);
              Ok ())
            else Eio.Fiber.await_cancel ())
      in
      if expect_exceeded then ignore (exceeded result)
      else check_bool "still supervised" true (result = Ok ()))

let intensity_window () =
  (* the window is half-open: an attempt at exactly [now - window] is forgotten *)
  window_case ~gap:10. ~expect_exceeded:false;
  window_case ~gap:9.9 ~expect_exceeded:true

let intensity_batch_counting () =
  run (fun clock ->
      let log, get = make_log () in
      let t1 = trigger () and t2 = trigger () in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log
                ~intensity:(intensity ~max_restarts:1 ())
                ~strategy:S.One_for_all
                [
                  scripted ~log "a" (fun _ -> Serve);
                  scripted ~log "x" (function
                    | 1 -> On (promise t1, Fail "one")
                    | 2 -> On (promise t2, Fail "two")
                    | _ -> Serve);
                  scripted ~log "c" (fun _ -> Serve);
                ]
            in
            fire t1;
            quiesce ();
            check_bool "three children restarted by one attempt: within a budget of one"
              true
              (states sup = [ ("a", 2); ("x", 2); ("c", 2) ]);
            fire t2;
            quiesce ();
            Eio.Fiber.await_cancel ())
      in
      let e = exceeded result in
      Alcotest.(check string) "the second attempt exceeds" "x" e.S.child_id;
      let l = get () in
      check_bool "every child was stopped and joined before the error" true
        (mem l "released a#2" && mem l "released x#2" && mem l "released c#2");
      check_bool "no third round of starts" false (mem l "start a#3"))

let intensity_failed_restart () =
  run (fun clock ->
      (* an incarnation that fails before it is ready needs another recovery: another attempt *)
      let log, get = make_log () in
      let t = trigger () in
      let e =
        exceeded
          (scoped (fun scope ->
               ignore
                 (start_ok ~scope ~clock ~log
                    ~intensity:(intensity ~max_restarts:2 ())
                    ~strategy:S.One_for_one
                    [
                      scripted ~log "x" (function
                        | 1 -> On (promise t, Fail "one")
                        | _ -> Early_fail "no start");
                    ]);
               fire t;
               Eio.Fiber.await_cancel ()))
      in
      let l = get () in
      check_int "initial start plus two attempts, and no more" 3 (starts_of l "x");
      check_bool "the last cause is the failed restart" true
        (match e.S.last_cause with Some (Cause.Fail "no start") -> true | _ -> false))

let invalid_configuration () =
  run (fun clock ->
      let log, get = make_log () in
      let refuses ?(intensity = intensity ()) children =
        ignore
          (scoped (fun scope ->
               (match
                  S.start ~scope ~clock ~intensity ~strategy:S.One_for_one children
                with
               | Error (`Invalid_supervisor _) -> ()
               | Ok _ | Error (`Start_failed _) ->
                   Alcotest.fail "the configuration must be refused");
               Ok ()))
      in
      let ok id = scripted ~log id (fun _ -> Serve) in
      refuses ~intensity:{ S.max_restarts = -1; window = Duration.seconds 1 } [ ok "a" ];
      refuses ~intensity:{ S.max_restarts = 1; window = Duration.zero } [ ok "a" ];
      refuses [ ok "a"; ok "a" ];
      refuses [ ok "a"; ok "" ];
      refuses [ scripted ~log ~significant:true "p" (fun _ -> Serve) ];
      check_strings "no child was started by any of them" [] (get ()))

(* ---- shutdown ------------------------------------------------------------------------ *)

let stop_one ~shutdown script =
  run (fun clock ->
      let log, get = make_log () in
      let elapsed = ref nan and outcome = ref None in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log ~strategy:S.One_for_one
                [ scripted ~log ~shutdown "c" script ]
            in
            let t0 = Eio.Time.now clock in
            outcome := Some (S.stop sup);
            elapsed := Eio.Time.now clock -. t0;
            Ok ())
      in
      check_bool "the owning scope is fine" true (result = Ok ());
      check_bool "stop reports Stopped" true (!outcome = Some S.Stopped);
      (get (), !elapsed))

let shutdown_modes () =
  let l, elapsed = stop_one ~shutdown:S.Infinity (fun _ -> Serve) in
  check_bool "Infinity: grace signal, then the child ends and is released" true
    (before l "stop c#1" "graceful c#1" && before l "graceful c#1" "released c#1");
  Alcotest.(check (float 0.0001)) "Infinity: no time passed" 0. elapsed;
  let l, elapsed = stop_one ~shutdown:(S.Timeout (Duration.seconds 5)) (fun _ -> Serve) in
  check_bool "Timeout: a child that honours the signal finishes early" true
    (mem l "graceful c#1" && mem l "released c#1");
  Alcotest.(check (float 0.0001))
    "Timeout: early completion does not wait out the deadline" 0. elapsed;
  let l, elapsed =
    stop_one ~shutdown:(S.Timeout (Duration.seconds 5)) (fun _ -> Ignore_stop)
  in
  check_bool "Timeout: a child that ignores the signal is cancelled and released" true
    (mem l "stop c#1" && mem l "released c#1" && not (mem l "graceful c#1"));
  Alcotest.(check (float 0.0001))
    "Timeout: exactly at the deadline on the supplied clock" 5. elapsed;
  let l, elapsed = stop_one ~shutdown:S.Brutal_kill (fun _ -> Serve) in
  check_bool "Brutal_kill: no grace signal, cancelled at once, finalizers still ran" true
    (mem l "stop c#1" && mem l "released c#1" && not (mem l "graceful c#1"));
  Alcotest.(check (float 0.0001)) "Brutal_kill: immediately" 0. elapsed

let timeout_is_not_a_kill () =
  run (fun clock ->
      let log, _ = make_log () in
      let gate, release = Eio.Promise.create () in
      let stopped = ref false in
      ignore
        (scoped (fun scope ->
             let sup =
               start_ok ~scope ~clock ~log ~strategy:S.One_for_one
                 [
                   S.child ~id:"slow"
                     ~shutdown:(S.Timeout (Duration.seconds 1))
                     (fun ctx ->
                       (* a finalizer no cancellation can interrupt until the gate opens *)
                       Eio.Switch.on_release (Scope.switch ctx.scope) (fun () ->
                           Eio.Promise.await gate;
                           log "finalizer done");
                       ctx.ready ();
                       Eio.Fiber.await_cancel ());
                 ]
             in
             Eio.Fiber.fork ~sw:(Scope.switch scope) (fun () ->
                 ignore (S.stop sup);
                 stopped := true);
             Eio.Time.sleep clock 3.;
             check_bool "past the deadline the stop still waits for the finalizer" false
               !stopped;
             Eio.Promise.resolve release ();
             quiesce ();
             check_bool "and returns once it finished" true !stopped;
             Ok ())))

let parent_cancellation_in_every_mode () =
  List.iter
    (fun shutdown ->
      run (fun clock ->
          let log, get = make_log () in
          let exit = ref None in
          Eio.Fiber.first
            (fun () ->
              exit :=
                Some
                  (Scope.run (fun sw ->
                       Scope.supervised_error ~sw (fun scope ->
                           ignore
                             (start_ok ~scope ~clock ~log ~strategy:S.One_for_one
                                [ scripted ~log ~shutdown "c" (fun _ -> Serve) ]);
                           Eio.Fiber.await_cancel ()))))
            (fun () -> quiesce ());
          let l = get () in
          check_bool "the child was cancelled and joined" true (mem l "released c#1");
          check_bool "parent cancellation takes precedence over a graceful stop" false
            (mem l "graceful c#1");
          check_bool "an interruption, never a recovery" true
            (match !exit with
            | Some (Exit.Failure cause) -> Cause.is_interrupt_only cause
            | _ -> false)))
    [ S.Brutal_kill; S.Timeout (Duration.seconds 5); S.Infinity ]

(* ---- simultaneous and stale exits -------------------------------------------------------- *)

let simultaneous_exits () =
  run (fun clock ->
      let log, get = make_log () in
      let t = trigger () in
      ignore
        (scoped (fun scope ->
             let sup =
               start_ok ~scope ~clock ~log
                 ~intensity:(intensity ~max_restarts:1 ())
                 ~strategy:S.One_for_all
                 [
                   scripted ~log "a" (function
                     | 1 -> On (promise t, Fail "a")
                     | _ -> Serve);
                   scripted ~log "b" (function
                     | 1 -> On (promise t, Fail "b")
                     | _ -> Serve);
                   scripted ~log "c" (fun _ -> Serve);
                 ]
             in
             fire t;
             quiesce ();
             check_bool "one group restart covers both exits" true
               (states sup = [ ("a", 2); ("b", 2); ("c", 2) ]);
             check_bool "the stale completion of an earlier incarnation starts nothing"
               false
               (mem (get ()) "start a#3" || mem (get ()) "start b#3");
             check_bool "within a budget of one attempt" false
               (mem (get ()) "shutting-down intensity");
             ignore (S.stop sup);
             Ok ())))

(* ---- SimpleOneForOne ------------------------------------------------------------------------ *)

let dynamic_template () =
  run (fun clock ->
      let log, get = make_log () in
      let triggers = Hashtbl.create 3 in
      let template =
        S.template ~id:"w" (fun (name, kind) (ctx : string S.context) ->
            log (fmt "start %s#%d" name ctx.incarnation);
            Eio.Switch.on_release (Scope.switch ctx.scope) (fun () ->
                log (fmt "released %s#%d" name ctx.incarnation));
            match kind with
            | `Bad -> Error "no start"
            | `Good ->
                ctx.ready ();
                if ctx.incarnation = 1 then
                  match Hashtbl.find_opt triggers name with
                  | Some p -> act ~log name ctx (On (p, Fail name))
                  | None -> act ~log name ctx Serve
                else act ~log name ctx Serve)
      in
      let a_trigger = trigger () in
      Hashtbl.replace triggers "a" (promise a_trigger);
      Hashtbl.replace triggers "b" (promise (trigger ()));
      let result =
        scoped (fun scope ->
            let simple =
              match
                S.start_simple ~scope ~clock ~intensity:(intensity ())
                  ~on_event:(fun e -> log (describe e))
                  template
              with
              | Ok simple -> simple
              | Error _ -> Alcotest.fail "start_simple"
            in
            let sup = S.supervisor simple in
            check_bool "no initial instance" true (S.children sup = []);
            let start input =
              match S.start_child simple input with
              | Ok id -> id
              | Error _ -> Alcotest.fail "start_child"
            in
            let a = start ("a", `Good) in
            let b = start ("b", `Good) in
            let c = start ("c", `Good) in
            check_bool "three instances, fresh ids" true
              (List.length (List.sort_uniq compare [ a; b; c ]) = 3);
            fire a_trigger;
            quiesce ();
            let l = get () in
            check_bool "only the failed instance restarted, with its retained input" true
              (mem l "start a#2" && (not (mem l "start b#2")) && not (mem l "start c#2"));
            check_bool "no sibling was stopped" false
              (mem l "stop b#1" || mem l "stop c#1");
            check_bool "the instance handle is stable across incarnations" true
              (List.assoc_opt a (states sup) = Some 2);
            (* explicit termination removes the instance and does not restart it *)
            check_bool "terminate" true (S.terminate_child sup b = Ok ());
            quiesce ();
            check_bool "terminated instance is gone" true
              (List.assoc_opt b (states sup) = None);
            check_bool "and was not restarted" false (mem (get ()) "start b#2");
            check_bool "terminating an unknown id is refused" true
              (S.terminate_child sup "nope" = Error `Unknown_child);
            (* an instance that fails before it is ready is not restarted *)
            (match S.start_child simple ("bad", `Bad) with
            | Error (`Start_failed f) ->
                check_bool "start failure names the cause" true
                  (f.S.cause = Cause.Fail "no start")
            | Ok _ | Error `Stopped -> Alcotest.fail "expected a start failure");
            check_bool "the failed instance is not listed" true
              (List.length (S.children sup) = 2);
            ignore (S.stop sup);
            check_bool "start_child after stop" true
              (S.start_child simple ("late", `Good) = Error `Stopped);
            Ok ())
      in
      check_bool "the owning scope is fine" true (result = Ok ()))

(* ---- significant children and auto shutdown ------------------------------------------------- *)

let auto_shutdown_run ~auto_shutdown ~children ~then_ =
  run (fun clock ->
      let log, get = make_log () in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log ~auto_shutdown ~strategy:S.One_for_one
                (children log)
            in
            then_ ~clock ~log ~get sup;
            Ok ())
      in
      check_bool "the owning scope is not failed by auto shutdown" true (result = Ok ()))

let auto_shutdown_never () =
  auto_shutdown_run ~auto_shutdown:S.Never
    ~children:(fun log ->
      [
        scripted ~log ~restart:S.Temporary "t" (fun _ -> Complete);
        scripted ~log "p" (fun _ -> Serve);
      ])
    ~then_:(fun ~clock:_ ~log:_ ~get:_ sup ->
      quiesce ();
      check_bool "the supervisor keeps running" true
        (List.assoc_opt "t"
           (List.map (fun (i : S.child_info) -> (i.id, i.state)) (S.children sup))
        = Some `Completed);
      check_bool "stopped explicitly" true (S.stop sup = S.Stopped))

let auto_shutdown_any () =
  List.iter
    (fun (restart, exit_) ->
      let t = trigger () in
      auto_shutdown_run ~auto_shutdown:S.Any_significant
        ~children:(fun log ->
          [
            scripted ~log "p" (fun _ -> Serve);
            scripted ~log ~restart ~significant:true "s" (fun _ -> On (promise t, exit_));
            scripted ~log "q" (fun _ -> Serve);
          ])
        ~then_:(fun ~clock:_ ~log:_ ~get sup ->
          fire t;
          check_bool "auto shutdown is the outcome, not an error" true
            (S.await sup = S.Auto_shutdown);
          let l = get () in
          check_bool "remaining children were stopped and awaited, in reverse order" true
            (before l "stop q#1" "stop p#1"
            && mem l "released q#1" && mem l "released p#1");
          check_bool "the terminal child's diagnostics survive" true
            (mem l (if exit_ = Complete then "exit s#1 normal" else "exit s#1 fail"))))
    [ (S.Temporary, Complete); (S.Temporary, Fail "s"); (S.Transient, Complete) ]

let auto_shutdown_transient_failure_restarts () =
  let t = trigger () in
  auto_shutdown_run ~auto_shutdown:S.Any_significant
    ~children:(fun log ->
      [
        scripted ~log ~restart:S.Transient ~significant:true "s" (function
          | 1 -> On (promise t, Fail "s")
          | _ -> Serve);
      ])
    ~then_:(fun ~clock:_ ~log:_ ~get:_ sup ->
      fire t;
      quiesce ();
      check_bool "a failure that restarts does not count as completion" true
        (states sup = [ ("s", 2) ]);
      check_bool "stopped explicitly" true (S.stop sup = S.Stopped))

let auto_shutdown_all () =
  let t1 = trigger () and t2 = trigger () in
  auto_shutdown_run ~auto_shutdown:S.All_significant
    ~children:(fun log ->
      [
        scripted ~log ~restart:S.Temporary ~significant:true "s1" (fun _ ->
            On (promise t1, Complete));
        scripted ~log ~restart:S.Temporary ~significant:true "s2" (fun _ ->
            On (promise t2, Fail "s2"));
        scripted ~log "p" (fun _ -> Serve);
      ])
    ~then_:(fun ~clock:_ ~log:_ ~get sup ->
      fire t1;
      quiesce ();
      check_bool "waits for the other significant child" true
        (List.assoc_opt "p" (states sup) = Some 1
        && not (mem (get ()) "shutting-down auto"));
      fire t2;
      check_bool "then shuts down" true (S.await sup = S.Auto_shutdown);
      check_bool "the remaining child was awaited" true (mem (get ()) "released p#1"))

let auto_shutdown_no_significant_children () =
  auto_shutdown_run ~auto_shutdown:S.All_significant
    ~children:(fun log ->
      [
        scripted ~log ~restart:S.Temporary "t" (fun _ -> Complete);
        scripted ~log "p" (fun _ -> Serve);
      ])
    ~then_:(fun ~clock:_ ~log:_ ~get:_ sup ->
      quiesce ();
      check_bool "an empty significant set never auto-stops" true
        (List.length (S.children sup) = 2);
      check_bool "stopped explicitly" true (S.stop sup = S.Stopped))

let auto_shutdown_ignores_induced_stops () =
  let t = trigger () in
  run (fun clock ->
      let log, get = make_log () in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log ~auto_shutdown:S.Any_significant
                ~strategy:S.One_for_all
                [
                  scripted ~log "a" (function
                    | 1 -> On (promise t, Fail "a")
                    | _ -> Serve);
                  scripted ~log ~restart:S.Temporary ~significant:true "s" (fun _ ->
                      Serve);
                ]
            in
            fire t;
            quiesce ();
            check_bool
              "a strategy-induced stop of a significant child is not a completion" true
              (not (mem (get ()) "shutting-down auto"));
            check_bool "the group was restarted; the Temporary collateral is gone" true
              (states sup = [ ("a", 2) ]);
            ignore (S.stop sup);
            Ok ())
      in
      check_bool "fine" true (result = Ok ());
      (* explicit removal is not a completion either, and empties the significant set *)
      let log, get = make_log () in
      let result =
        scoped (fun scope ->
            let sup =
              start_ok ~scope ~clock ~log ~auto_shutdown:S.Any_significant
                ~strategy:S.One_for_one
                [
                  scripted ~log ~restart:S.Temporary ~significant:true "s" (fun _ ->
                      Serve);
                ]
            in
            check_bool "terminate" true (S.terminate_child sup "s" = Ok ());
            quiesce ();
            check_bool "explicit removal does not auto-stop" false
              (mem (get ()) "shutting-down auto");
            ignore (S.stop sup);
            Ok ())
      in
      check_bool "fine" true (result = Ok ()))

let auto_shutdown_does_not_hide_intensity () =
  run (fun clock ->
      let log, _ = make_log () in
      let result =
        scoped (fun scope ->
            ignore
              (start_ok ~scope ~clock ~log
                 ~intensity:(intensity ~max_restarts:1 ())
                 ~auto_shutdown:S.Any_significant ~strategy:S.One_for_one
                 [
                   scripted ~log ~restart:S.Temporary ~significant:true "s" (fun _ ->
                       Serve);
                   scripted ~log "x" (fun _ -> Fail "loop");
                 ]);
            Eio.Fiber.await_cancel ())
      in
      let e = exceeded result in
      Alcotest.(check string) "exhaustion stays a typed failure" "x" e.S.child_id)

(* ---- nested supervisors: ownership and propagation without links -------------------------- *)

type inner_error = [ `Restart_intensity_exceeded of string S.intensity_error ]

let nested () =
  run (fun clock ->
      let log, get = make_log () in
      let group_starts = ref 0 in
      let trig = trigger () in
      let group =
        S.child ~id:"group" (fun (ctx : inner_error S.context) ->
            incr group_starts;
            log (fmt "group start %d" !group_starts);
            match
              S.start ~scope:ctx.scope ~clock
                ~intensity:(intensity ~max_restarts:0 ())
                ~on_event:(fun e -> log ("inner " ^ describe e))
                ~strategy:S.One_for_all
                [
                  scripted ~log "x" (fun _ ->
                      if !group_starts = 1 then On (promise trig, Fail "x") else Serve);
                  scripted ~log "y" (fun _ -> Serve);
                ]
            with
            | Error _ -> Alcotest.fail "inner start"
            | Ok inner ->
                ctx.ready ();
                Eio.Promise.await ctx.stop_requested;
                ignore (S.stop inner);
                Ok ())
      in
      let result =
        scoped (fun scope ->
            let outer =
              start_ok ~scope ~clock ~log ~intensity:(intensity ())
                ~strategy:S.One_for_one [ group ]
            in
            fire trig;
            quiesce ();
            let l = get () in
            check_bool
              "the inner intensity error ended the child's scope as a typed failure" true
              (mem l "exit group#1 fail" && mem l "inner shutting-down intensity");
            check_bool
              "the outer supervisor restarted the group with a fresh inner supervisor"
              true
              (mem l "group start 2" && List.assoc_opt "group" (states outer) = Some 2);
            check_bool "inner children were joined before the child completed" true
              (before l "released y#1" "exit group#1 fail"
              && before l "released x#1" "exit group#1 fail");
            ignore (S.stop outer);
            let l = get () in
            let last line =
              let rec go i found = function
                | [] -> found
                | x :: rest -> go (i + 1) (if x = line then i else found) rest
              in
              go 0 (-1) l
            in
            check_bool "stopping the outer stops the inner group, in reverse order" true
              (last "inner stop y#1" >= 0
              && last "inner stop y#1" < last "inner stop x#1"
              && last "inner stop x#1" < last "exit group#2 normal induced");
            check_bool "and its children were released before the group completed" true
              (last "released x#1" < last "exit group#2 normal induced");
            Ok ())
      in
      ignore result)

(* ---- republishing handles through an Agent; a fresh Agent per incarnation ---------------- *)

let republish_actor_handle () =
  run (fun clock ->
      let log, _ = make_log () in
      let seen = ref [] in
      ignore
        (scoped (fun scope ->
             let registry =
               Agent.create ~sw:(Scope.switch scope) ~init:(fun () -> None) ()
             in
             let service =
               S.child ~id:"service" (fun ctx ->
                   let actor =
                     Actor.create ~sw:(Scope.switch ctx.scope) ~init:ctx.incarnation
                       ~handle:(fun state -> function
                         | `Get -> Ok (state, state) | `Crash -> raise (Boom "service"))
                       ()
                   in
                   ignore (Agent.update registry ~fn:(fun _ -> Some actor));
                   ctx.ready ();
                   Eio.Promise.await ctx.stop_requested;
                   Ok ())
             in
             let client =
               S.child ~id:"client" (fun ctx ->
                   (match Agent.get registry ~fn:Fun.id with
                   | Ok (Some actor) -> (
                       match Actor.ask actor `Get with
                       | Ok n -> seen := n :: !seen
                       | Error _ -> seen := -1 :: !seen)
                   | _ -> seen := -2 :: !seen);
                   ctx.ready ();
                   Eio.Promise.await ctx.stop_requested;
                   Ok ())
             in
             let sup =
               start_ok ~scope ~clock ~log ~strategy:S.Rest_for_one [ service; client ]
             in
             let current () =
               match Agent.get registry ~fn:Fun.id with
               | Ok (Some actor) -> actor
               | _ -> Alcotest.fail "no handle published"
             in
             let first = current () in
             check_bool "the first incarnation answers" true (Actor.ask first `Get = Ok 1);
             Actor.tell first `Crash;
             quiesce ();
             let second = current () in
             check_bool "the replacement is republished through the Agent" true
               (Actor.ask second `Get = Ok 2);
             check_bool "the old handle is a stopped actor, not revived" true
               (Actor.ask first `Get = Error `Actor_stopped);
             check_bool
               "the dependent (Rest_for_one) started after the service was ready and \
                read the new handle"
               true
               (!seen = [ 2; 1 ]);
             ignore (S.stop sup);
             Ok ())))

let fresh_agent_per_incarnation () =
  run (fun clock ->
      let log, get = make_log () in
      ignore
        (scoped (fun scope ->
             let registry =
               Agent.create ~sw:(Scope.switch scope) ~init:(fun () -> None) ()
             in
             let holder =
               S.child ~id:"holder" (fun ctx ->
                   let agent =
                     Agent.create ~sw:(Scope.switch ctx.scope)
                       ~init:(fun () -> ctx.incarnation * 100)
                       ()
                   in
                   ignore (Agent.update registry ~fn:(fun _ -> Some agent));
                   ctx.ready ();
                   Eio.Promise.await ctx.stop_requested;
                   Ok ())
             in
             let sup = start_ok ~scope ~clock ~log ~strategy:S.One_for_one [ holder ] in
             let current () =
               match Agent.get registry ~fn:Fun.id with
               | Ok (Some agent) -> agent
               | _ -> Alcotest.fail "no agent published"
             in
             let first = current () in
             check_bool "state of the first agent" true
               (Agent.get first ~fn:Fun.id = Ok 100);
             (* a callback that raises fails the agent's switch: the child's scope, supervised *)
             ignore (Agent.cast first ~fn:(fun _ -> raise (Boom "callback")));
             quiesce ();
             let second = current () in
             check_bool "a fresh agent, initialized again" true
               (Agent.get second ~fn:Fun.id = Ok 200);
             check_bool "the stopped handle is not revived" true
               (Agent.get first ~fn:Fun.id = Error `Agent_stopped);
             check_bool "the defect was reported by the supervisor" true
               (mem (get ()) "exit holder#1 die");
             ignore (S.stop sup);
             Ok ())))

let tests =
  [
    ( "Supervisor nactor-d120",
      [
        Alcotest.test_case "nactor-d120 strategies x restart types x outcomes" `Quick
          strategy_table;
        Alcotest.test_case "nactor-d120 defects are reported with the original exception"
          `Quick defect_reporting;
        Alcotest.test_case "nactor-d120 cleanup failures are never discarded" `Quick
          cleanup_failures;
        Alcotest.test_case "nactor-d120 external cancellation keeps its identity" `Quick
          external_cancellation;
        Alcotest.test_case "nactor-d120 intensity budget" `Quick intensity_budget;
        Alcotest.test_case "nactor-d120 intensity window is half-open" `Quick
          intensity_window;
        Alcotest.test_case "nactor-d120 a recovery batch is one attempt" `Quick
          intensity_batch_counting;
        Alcotest.test_case "nactor-d120 a failed restart is another attempt" `Quick
          intensity_failed_restart;
        Alcotest.test_case "nactor-d120 invalid configuration starts nothing" `Quick
          invalid_configuration;
        Alcotest.test_case "nactor-d120 shutdown modes" `Quick shutdown_modes;
        Alcotest.test_case "nactor-d120 a timeout is not a kill" `Quick
          timeout_is_not_a_kill;
        Alcotest.test_case "nactor-d120 parent cancellation in every shutdown mode" `Quick
          parent_cancellation_in_every_mode;
        Alcotest.test_case "nactor-d120 simultaneous and stale exits" `Quick
          simultaneous_exits;
        Alcotest.test_case "nactor-d120 dynamic template instances" `Quick
          dynamic_template;
        Alcotest.test_case "nactor-d120 auto_shutdown Never" `Quick auto_shutdown_never;
        Alcotest.test_case "nactor-d120 auto_shutdown Any_significant" `Quick
          auto_shutdown_any;
        Alcotest.test_case
          "nactor-d120 a restarting Transient failure is not a completion" `Quick
          auto_shutdown_transient_failure_restarts;
        Alcotest.test_case "nactor-d120 auto_shutdown All_significant" `Quick
          auto_shutdown_all;
        Alcotest.test_case "nactor-d120 no significant children" `Quick
          auto_shutdown_no_significant_children;
        Alcotest.test_case "nactor-d120 induced stops and removal are not completions"
          `Quick auto_shutdown_ignores_induced_stops;
        Alcotest.test_case "nactor-d120 intensity exhaustion is never auto shutdown"
          `Quick auto_shutdown_does_not_hide_intensity;
        Alcotest.test_case "nactor-d120 nested supervisors" `Quick nested;
        Alcotest.test_case "nactor-d120 handles are republished through an Agent" `Quick
          republish_actor_handle;
        Alcotest.test_case "nactor-75ef nactor-d120 a fresh Agent per incarnation" `Quick
          fresh_agent_per_incarnation;
      ] );
  ]
