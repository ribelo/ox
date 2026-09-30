(* ^nstress-mvpj: Concurrent's fail-fast/first-success laws (concurrent.mli),
   Scope's typed boundary law (scope.mli), and ADR-0002. Real Eio fibers on a
   virtual clock: shrinking changes outcomes and timing, not wall-clock sleeps. *)
open Ox

type outcome = Success | Typed | Defect | Cancel
type branch = { outcome : outcome; delay : int }
type operation = Par | All | For_each of int | Race | Supervised

exception Boom of int
exception External of int

type observed =
  | Values of int list
  | Typed_error of int
  | Race_errors of int Cause.t
  | Raised of exn

let pp_outcome = function
  | Success -> "ok"
  | Typed -> "error"
  | Defect -> "exception"
  | Cancel -> "cancel"

let print_pattern branches =
  branches
  |> List.mapi (fun i b -> Printf.sprintf "%d:%s@%d" i (pp_outcome b.outcome) b.delay)
  |> String.concat "; "

let fail fmt = Printf.ksprintf QCheck2.Test.fail_report fmt
let ensure condition fmt = if not condition then fail "%s" fmt
let deadline i b = float_of_int ((b.delay * 16) + i + 1)

let typed_errors cause =
  let rec collect = function
    | Cause.Fail i -> [ i ]
    | Cause.Concurrent causes -> List.concat_map collect causes
    | _ -> fail "race returned a non-typed error cause"
  in
  collect cause

let run ?cancel_at operation branches =
  Eio_mock.Backend.run_full (fun env ->
      Eio.Fiber.with_binding env#debug#traceln
        {
          Eio.Debug.traceln =
            (fun ?__POS__:_ fmt -> Format.ifprintf Format.err_formatter fmt);
        }
        (fun () ->
          Eio.Switch.run (fun control_sw ->
              let clock = env#clock in
              let context, publish = Eio.Promise.create () in
              let array = Array.of_list branches in
              let count = Array.length array in
              let started = Array.make count false
              and released = Array.make count false in
              let active = ref 0 and high_water = ref 0 and events = ref [] in
              (* Independent caller, not a branch throwing Cancelled. Each generated
             Cancel identifies a position and deadline for external cancellation. *)
              let cancels =
                List.mapi (fun i b -> (i, b)) branches
                |> List.filter (fun (_, b) -> b.outcome = Cancel)
                |> List.sort (fun (i, a) (j, b) ->
                    Float.compare (deadline i a) (deadline j b))
              in
              (match cancels with
              | [] -> ()
              | (i, b) :: _ ->
                  Eio.Fiber.fork_daemon ~sw:control_sw (fun () ->
                      let cc = Eio.Promise.await context in
                      Eio.Time.sleep_until clock
                        (Option.value cancel_at ~default:(deadline i b));
                      events := (i, Cancel) :: !events;
                      Eio.Cancel.cancel cc (External i);
                      `Stop_daemon));
              let task i () =
                ensure (not started.(i)) "a task ran twice";
                started.(i) <- true;
                incr active;
                high_water := max !high_water !active;
                Fun.protect
                  (fun () ->
                    let b = array.(i) in
                    Eio.Time.sleep_until clock (deadline i b);
                    if b.outcome = Cancel then Eio.Fiber.await_cancel ();
                    events := (i, b.outcome) :: !events;
                    match b.outcome with
                    | Success -> Ok i
                    | Typed -> Error i
                    | Defect -> raise (Boom i)
                    | Cancel -> assert false)
                  ~finally:(fun () ->
                    (* A suspension during protected release makes a census stronger
                   than counting exception unwinding alone. *)
                    Eio.Cancel.protect (fun () -> Eio.Time.sleep clock 0.125);
                    released.(i) <- true;
                    decr active)
              in
              let capture sw =
                try
                  match operation with
                  | Par -> (
                      match Concurrent.par ~sw (task 0) (task 1) with
                      | Ok (a, b) -> Values [ a; b ]
                      | Error i -> Typed_error i)
                  | All -> (
                      match Concurrent.all ~sw (List.init count task) with
                      | Ok values -> Values values
                      | Error i -> Typed_error i)
                  | For_each concurrency -> (
                      match
                        Concurrent.for_each ~sw ~concurrency (List.init count Fun.id)
                          (fun i -> task i ())
                      with
                      | Ok values -> Values values
                      | Error i -> Typed_error i)
                  | Race -> (
                      match Concurrent.race ~sw (List.init count task) with
                      | Ok i -> Values [ i ]
                      | Error cause -> Race_errors cause)
                  | Supervised -> (
                      match
                        Scope.supervised_error ~sw (fun scope ->
                            for i = 0 to count - 2 do
                              ignore (Scope.fork_error scope (task i))
                            done;
                            task (count - 1) ())
                      with
                      | Ok i -> Values [ i ]
                      | Error i -> Typed_error i)
                with ex -> Raised ex
              in
              let observed =
                Eio.Cancel.sub (fun cc ->
                    Eio.Promise.resolve publish cc;
                    let result =
                      Eio.Switch.run (fun sw ->
                          let result = capture sw in
                          (* Before the test's parent switch can rescue a leaked fiber. *)
                          ensure (!active = 0) "combinator returned with live fibers";
                          Array.iteri
                            (fun i did_start ->
                              ensure
                                ((not did_start) || released.(i))
                                "a started fiber was not awaited")
                            started;
                          result)
                    in
                    result)
              in
              (observed, List.rev !events, started, !high_water))))

let verify operation branches =
  let observed, events, started, high_water = run operation branches in
  let count = List.length branches in
  (match operation with
  | For_each concurrency ->
      ensure (high_water <= concurrency) "for_each exceeded concurrency"
  | _ -> ());
  let terminal =
    List.find_opt
      (fun (_, outcome) ->
        match (operation, outcome) with
        | Race, (Success | Defect | Cancel) -> true
        | Race, Typed -> false
        | _, (Typed | Defect | Cancel) -> true
        | _, Success -> false)
      events
  in
  let matches =
    match (terminal, observed) with
    | Some (i, Cancel), Raised (Eio.Cancel.Cancelled (External j)) -> i = j
    | Some (i, Defect), Raised (Boom j) -> i = j
    | Some (i, Typed), Typed_error j -> i = j
    | Some (i, Success), Values [ j ] when operation = Race -> i = j
    | None, Race_errors cause when operation = Race ->
        typed_errors cause = List.init count Fun.id
    | None, Values actual ->
        Array.for_all Fun.id started
        && actual
           = if operation = Supervised then [ count - 1 ] else List.init count Fun.id
    | _ -> false
  in
  (if not matches then
     let description =
       match observed with
       | Values xs -> "Ok [" ^ String.concat "," (List.map string_of_int xs) ^ "]"
       | Typed_error i -> "Error " ^ string_of_int i
       | Race_errors _ -> "Error Cause"
       | Raised ex -> Printexc.to_string ex
     in
     fail "law violation for [%s]: %s" (print_pattern branches) description);
  (* For unbounded admission the independently generated schedule, not merely
     the observed trace, predicts which outcome is allowed to terminate. *)
  (match operation with
  | For_each concurrency when concurrency < count -> ()
  | _ ->
      let sorted =
        List.mapi (fun i b -> (i, b)) branches
        |> List.sort (fun (i, a) (j, b) -> Float.compare (deadline i a) (deadline j b))
      in
      let expected =
        List.find_opt
          (fun (_, b) ->
            match operation with Race -> b.outcome <> Typed | _ -> b.outcome <> Success)
          sorted
      in
      ensure
        (Option.map (fun (i, b) -> (i, b.outcome)) expected = terminal)
        "terminal event disagrees with generated schedule");
  true

let generator count =
  let open QCheck2.Gen in
  let branch =
    map2
      (fun outcome delay -> { outcome; delay })
      (oneof_list [ Success; Typed; Defect; Cancel ])
      (int_range 0 8)
  in
  list_size count branch

(* Caller cancellation during suspended loser cleanup must win over a typed
   failure which the boundary has already observed; Scope.exit_on_error says so. *)
let cancel_during_release operation position =
  let count = if operation = Par then 2 else 6 in
  let position = position mod count in
  let caller = (position + 1) mod count in
  let branches =
    List.init count (fun i ->
        {
          outcome =
            (if i = position then Typed else if i = caller then Cancel else Success);
          delay = (if i = position then 0 else 8);
        })
  in
  let cancel_at = float_of_int (position + 1) +. 0.1875 in
  let observed, _, _, _ = run ~cancel_at operation branches in
  match observed with
  | Raised (Eio.Cancel.Cancelled (External i)) when i = caller -> true
  | _ -> fail "caller cancellation during typed-failure release was swallowed"

let properties () =
  let make name operation size =
    QCheck2.Test.make ~name ~count:1500 ~print:print_pattern (generator size)
      (verify operation)
  in
  let open QCheck2.Gen in
  [
    make "par: fail fast, ordered pair, external cancel and await" Par (return 2);
    make "all: fail fast, ordered output and await" All (int_range 1 8);
    make "for_each: ordered output and bounded admission" (For_each 2) (int_range 1 8);
    make "race: first success, all-error cause and await losers" Race (int_range 1 8);
    make "Scope.supervised_error: body and every child position" Supervised
      (int_range 1 8);
    QCheck2.Test.make ~name:"caller cancellation wins during typed-error teardown"
      ~count:500 ~print:string_of_int (int_range 0 5) (fun position ->
        List.for_all
          (fun operation -> cancel_during_release operation position)
          [ Par; All; For_each 6; Supervised ]);
  ]

let positional_matrix () =
  List.iter
    (fun operation ->
      let count = if operation = Par then 2 else 6 in
      List.iter
        (fun outcome ->
          for position = 0 to count - 1 do
            List.iter
              (fun delay ->
                let branches =
                  List.init count (fun i ->
                      {
                        outcome = (if i = position then outcome else Success);
                        delay = (if i = position then delay else 4);
                      })
                in
                ignore (verify operation branches))
              [ 0; 4; 8 ]
          done)
        [ Success; Typed; Defect; Cancel ])
    [ Par; All; For_each 2; For_each 6; Race; Supervised ];
  ignore (verify All []);
  ignore (verify (For_each 2) []);
  (* No success: every typed rejection survives, in input order. *)
  ignore (verify Race (List.init 8 (fun i -> { outcome = Typed; delay = 8 - i })))

let () =
  let rng = Stress_support.random ~default:6075 () in
  let code =
    Eio_mock.Backend.run_full (fun env ->
        (* The auto-clock advances outside its inner backend's fiber handler, so
         bind trace on this outer runner fiber rather than changing global logs. *)
        Eio.Fiber.with_binding env#debug#traceln
          {
            Eio.Debug.traceln =
              (fun ?__POS__:_ fmt -> Format.ifprintf Format.err_formatter fmt);
          }
          (fun () ->
            positional_matrix ();
            QCheck_base_runner.run_tests ~rand:rng ~verbose:true (properties ())))
  in
  exit code
