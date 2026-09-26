open Eta

let dur_ms = Duration.ms
let some_dur = Alcotest.option (Alcotest.testable Duration.pp Duration.equal)
let dur = Alcotest.testable Duration.pp Duration.equal

let next_delay ?random ?(now_ms = 0) ?(input = ()) schedule ~step =
  let rec advance driver remaining =
    match Schedule.next ~now_ms ~input driver with
    | None -> None
    | Some (metadata, driver) ->
        if remaining <= 0 then Some metadata.delay else advance driver (remaining - 1)
  in
  advance (Schedule.start ?random schedule) step

let next_continue ?(now_ms = 0) ?(input = ()) driver =
  match Schedule.next ~now_ms ~input driver with
  | None -> Alcotest.fail "schedule ended"
  | Some (metadata, driver) -> (metadata, driver)

let next_continue_with_input ?(now_ms = 0) ~input driver =
  match Schedule.next ~now_ms ~input driver with
  | None -> Alcotest.fail "schedule ended"
  | Some (metadata, driver) -> (metadata, driver)

let test_duration_constructors () =
  Alcotest.(check dur) "seconds" (Duration.ms 1_000) (Duration.seconds 1);
  Alcotest.(check dur) "minutes" (Duration.seconds 60) (Duration.minutes 1);
  Alcotest.(check dur) "hours" (Duration.minutes 60) (Duration.hours 1);
  Alcotest.(check dur) "days" (Duration.hours 24) (Duration.days 1);
  Alcotest.(check dur) "weeks" (Duration.days 7) (Duration.weeks 1)

let test_duration_ordering () =
  Alcotest.(check int) "lt" (-1) (Duration.compare (Duration.ms 1) (Duration.ms 2));
  Alcotest.(check int) "eq" 0 (Duration.compare (Duration.ms 2) (Duration.ms 2));
  Alcotest.(check int) "gt" 1 (Duration.compare (Duration.ms 2) (Duration.ms 1));
  Alcotest.(check bool)
    "between" true
    (Duration.between ~min:(Duration.minutes 59) ~max:(Duration.minutes 61)
       (Duration.hours 1));
  Alcotest.(check bool)
    "below range" false
    (Duration.between ~min:(Duration.minutes 59) ~max:(Duration.minutes 61)
       (Duration.minutes 58));
  Alcotest.(check bool)
    "above range" false
    (Duration.between ~min:(Duration.minutes 59) ~max:(Duration.minutes 61)
       (Duration.minutes 62))

let test_duration_algebra () =
  Alcotest.(check dur)
    "sum" (Duration.minutes 1)
    (Duration.add (Duration.seconds 30) (Duration.seconds 30));
  Alcotest.(check dur)
    "subtract clamps at zero" Duration.zero
    (Duration.subtract (Duration.seconds 30) (Duration.seconds 40));
  Alcotest.(check dur)
    "times" (Duration.minutes 1)
    (Duration.times (Duration.seconds 1) 60);
  Alcotest.(check some_dur)
    "divide"
    (Some (Duration.seconds 30))
    (Duration.divide (Duration.minutes 1) 2);
  Alcotest.(check some_dur) "divide by zero" None (Duration.divide (Duration.minutes 1) 0)

let test_duration_scale_identity_at_max () =
  Alcotest.(check int)
    "scale by 1.0 must be the identity" max_int
    (Duration.to_ms (Duration.scale (Duration.ms max_int) 1.0))

let test_duration_overflow () =
  let overflowing_hours = (max_int / 3_600_000) + 1 in
  Alcotest.check_raises "large hours overflow" (Invalid_argument "Duration.hours")
    (fun () -> ignore (Duration.hours overflowing_hours));
  Alcotest.check_raises "add overflow" (Invalid_argument "Duration.add") (fun () ->
      ignore (Duration.add (Duration.ms max_int) (Duration.ms 1)));
  Alcotest.check_raises "times overflow" (Invalid_argument "Duration.times") (fun () ->
      ignore (Duration.times (Duration.ms max_int) 2))

let test_duration_min_max_clamp () =
  Alcotest.(check dur)
    "max" (Duration.ms 2)
    (Duration.max (Duration.ms 1) (Duration.ms 2));
  Alcotest.(check dur)
    "min" (Duration.ms 1)
    (Duration.min (Duration.ms 1) (Duration.ms 2));
  Alcotest.(check dur)
    "clamp lower" (Duration.ms 2)
    (Duration.clamp ~min:(Duration.ms 2) ~max:(Duration.ms 3) (Duration.ms 1));
  Alcotest.(check dur)
    "clamp upper" (Duration.ms 3)
    (Duration.clamp ~min:(Duration.ms 2) ~max:(Duration.ms 3) (Duration.ms 4));
  Alcotest.(check dur)
    "clamp inside" (Duration.minutes 90)
    (Duration.clamp ~min:(Duration.minutes 60) ~max:(Duration.minutes 120)
       (Duration.minutes 90));
  Alcotest.(check dur)
    "clamp equal bounds" (Duration.ms 2)
    (Duration.clamp ~min:(Duration.ms 2) ~max:(Duration.ms 2) (Duration.ms 4));
  Alcotest.check_raises "clamp reversed bounds" (Invalid_argument "Duration.clamp")
    (fun () ->
      ignore (Duration.clamp ~min:(Duration.ms 5) ~max:(Duration.ms 2) (Duration.ms 4)));
  Alcotest.(check bool)
    "between empty interval is false" false
    (Duration.between ~min:(Duration.ms 5) ~max:(Duration.ms 2) (Duration.ms 4))

let test_duration_zero_detection_and_conversion () =
  Alcotest.(check bool) "zero is zero" true (Duration.is_zero Duration.zero);
  Alcotest.(check bool) "positive is not zero" false (Duration.is_zero (Duration.ms 1));
  Alcotest.(check int) "seconds to ms" 2_000 (Duration.to_ms (Duration.seconds 2));
  Alcotest.(check (float 0.0))
    "ms to seconds float" 1.5
    (Duration.to_seconds_float (Duration.ms 1_500))

let test_duration_humanize () =
  Alcotest.(check string) "zero" "0" (Duration.humanize Duration.zero);
  Alcotest.(check string) "millis" "42ms" (Duration.humanize (Duration.ms 42));
  Alcotest.(check string)
    "second and millis" "1s 1ms"
    (Duration.humanize (Duration.ms 1_001));
  Alcotest.(check string)
    "compound" "2d 3h 4m 5s 6ms"
    (Duration.humanize Duration.(days 2 + hours 3 + minutes 4 + seconds 5 + ms 6))

let test_recurs () =
  let s = Schedule.recurs 3 in
  Alcotest.(check some_dur) "0" (Some Duration.zero) (next_delay s ~step:0);
  Alcotest.(check some_dur) "exhausted" None (next_delay s ~step:3)

let test_recurs_driver_yields_exactly_n_delays () =
  let rec collect driver acc =
    match Schedule.next ~now_ms:0 ~input:() driver with
    | None -> List.rev acc
    | Some (metadata, next) -> collect next (metadata.delay :: acc)
  in
  Alcotest.(check (list dur))
    "three recurrences"
    [ Duration.zero; Duration.zero; Duration.zero ]
    (collect (Schedule.start (Schedule.recurs 3)) [])

let test_recurs_rejects_max_int_at_construction () =
  Alcotest.check_raises "recurs max_int"
    (Invalid_argument "Schedule.recurs: count must be < max_int") (fun () ->
      ignore (Schedule.recurs max_int))

let test_recurs_accepts_max_int_minus_one_at_construction () =
  ignore (Schedule.recurs (max_int - 1) : (_, _) Schedule.t)

let expect_recurs_zero_terminal label schedule =
  let first, driver =
    match Schedule.step ~now_ms:0 ~input:() (Schedule.start schedule) with
    | Schedule.Done metadata, driver -> (metadata, driver)
    | Schedule.Continue metadata, _ ->
        Alcotest.failf "%s: expected immediate Done, got Continue attempt=%d" label
          metadata.attempt
  in
  Alcotest.(check int) (label ^ " terminal attempt") 1 first.attempt;
  Alcotest.(check int) (label ^ " terminal output") 0 first.output;
  Alcotest.(check dur) (label ^ " terminal delay") Duration.zero first.delay;
  match Schedule.step ~now_ms:0 ~input:() driver with
  | Schedule.Done replay, _ ->
      Alcotest.(check int) (label ^ " frozen attempt") 1 replay.attempt;
      Alcotest.(check int) (label ^ " frozen output") 0 replay.output;
      Alcotest.(check dur) (label ^ " frozen delay") Duration.zero replay.delay
  | Schedule.Continue _, _ -> Alcotest.failf "%s: frozen Done restarted" label

let test_recurs_negative_matches_zero_terminal_and_replay () =
  expect_recurs_zero_terminal "recurs 0" (Schedule.recurs 0);
  expect_recurs_zero_terminal "recurs -1" (Schedule.recurs (-1));
  expect_recurs_zero_terminal "recurs min_int" (Schedule.recurs min_int)

let test_exponential () =
  let s = Schedule.exponential ~factor:2.0 (dur_ms 10) in
  Alcotest.(check some_dur) "step 0" (Some (dur_ms 10)) (next_delay s ~step:0);
  Alcotest.(check some_dur) "step 2 = 40ms" (Some (dur_ms 40)) (next_delay s ~step:2)

let test_exponential_omitted_factor_defaults_to_two () =
  let rec loop driver expected =
    match expected with
    | [] -> ()
    | ms :: rest -> (
        match Schedule.step ~now_ms:0 ~input:() driver with
        | Schedule.Done _, _ -> Alcotest.fail "expected Continue"
        | Schedule.Continue metadata, driver ->
            Alcotest.(check dur)
              (Printf.sprintf "default factor delay %dms" ms)
              (dur_ms ms) metadata.delay;
            Alcotest.(check dur)
              (Printf.sprintf "default factor output %dms" ms)
              (dur_ms ms) metadata.output;
            loop driver rest)
  in
  loop (Schedule.start (Schedule.exponential (dur_ms 10))) [ 10; 20; 40 ]

let test_exponential_saturates_on_overflow () =
  let s = Schedule.exponential ~factor:2.0 (Duration.ms max_int) in
  Alcotest.(check some_dur)
    "large exponent saturates"
    (Some (Duration.ms max_int))
    (next_delay s ~step:1024)

let collect_exponential_steps n schedule =
  let rec loop i driver acc =
    if i = n then List.rev acc
    else
      match Schedule.step ~now_ms:0 ~input:() driver with
      | Schedule.Done _, _ -> Alcotest.fail "exponential terminated"
      | Schedule.Continue metadata, driver ->
          loop (i + 1) driver ((metadata.delay, metadata.output) :: acc)
  in
  loop 0 (Schedule.start schedule) []

let assert_zero_steps label n schedule =
  collect_exponential_steps n schedule
  |> List.iteri (fun i (delay, output) ->
      Alcotest.(check dur) (Printf.sprintf "%s step %d delay" label i) Duration.zero delay;
      Alcotest.(check dur)
        (Printf.sprintf "%s step %d output" label i)
        Duration.zero output)

let test_exponential_zero_survives_max_float_power () =
  let schedule = Schedule.exponential ~factor:max_float Duration.zero in
  assert_zero_steps "zero base max_float" 4 schedule

let test_exponential_positive_base_saturates_max_float () =
  let schedule = Schedule.exponential ~factor:max_float (Duration.ms 1) in
  match collect_exponential_steps 3 schedule with
  | [ (d0, o0); (d1, o1); (d2, o2) ] ->
      Alcotest.(check dur) "step 0 delay" (Duration.ms 1) d0;
      Alcotest.(check dur) "step 0 output" (Duration.ms 1) o0;
      Alcotest.(check dur) "step 1 delay" (Duration.ms max_int) d1;
      Alcotest.(check dur) "step 1 output" (Duration.ms max_int) o1;
      Alcotest.(check dur) "step 2 delay" (Duration.ms max_int) d2;
      Alcotest.(check dur) "step 2 output" (Duration.ms max_int) o2
  | _ -> Alcotest.fail "expected 3 steps"

let test_exponential_zero_base_factors () =
  assert_zero_steps "factor 0" 3 (Schedule.exponential ~factor:0.0 Duration.zero);
  assert_zero_steps "factor 1" 3 (Schedule.exponential ~factor:1.0 Duration.zero);
  assert_zero_steps "decay 0.5" 3 (Schedule.exponential ~factor:0.5 Duration.zero)

let exponential_factor_exn =
  Invalid_argument "Schedule.exponential factor: expected finite nonnegative"

let jitter_min_exn = Invalid_argument "Schedule.jittered min: expected finite nonnegative"
let jitter_max_exn = Invalid_argument "Schedule.jittered max: expected finite nonnegative"
let jitter_reversed_exn = Invalid_argument "Schedule.jittered: min exceeds max"

let test_exponential_rejects_invalid_factor_at_construction () =
  let reject label factor =
    Alcotest.check_raises label exponential_factor_exn (fun () ->
        ignore (Schedule.exponential ~factor Duration.zero))
  in
  reject "nan" nan;
  reject "+infinity" infinity;
  reject "-infinity" neg_infinity;
  reject "negative" (-1.0)

let test_exponential_accepts_zero_signed_zero_unit_decay () =
  List.iter
    (fun factor ->
      assert_zero_steps
        (Printf.sprintf "factor %g" factor)
        2
        (Schedule.exponential ~factor Duration.zero))
    [ 0.0; -0.0; 1.0; 0.5 ]

let test_jittered_rejects_invalid_bounds_at_construction () =
  let inner = Schedule.spaced (Duration.ms 10) in
  let reject_min label min =
    Alcotest.check_raises label jitter_min_exn (fun () ->
        ignore (Schedule.jittered ~min ~max:1.0 inner))
  in
  let reject_max label max =
    Alcotest.check_raises label jitter_max_exn (fun () ->
        ignore (Schedule.jittered ~min:0.0 ~max inner))
  in
  reject_min "min nan" nan;
  reject_min "min +inf" infinity;
  reject_min "min -inf" neg_infinity;
  reject_min "min negative" (-0.1);
  reject_max "max nan" nan;
  reject_max "max +inf" infinity;
  reject_max "max -inf" neg_infinity;
  reject_max "max negative" (-0.1);
  Alcotest.check_raises "reversed" jitter_reversed_exn (fun () ->
      ignore (Schedule.jittered ~min:1.2 ~max:0.8 inner))

let test_jittered_accepts_equal_signed_zero_and_defaults () =
  let inner = Schedule.spaced (Duration.ms 100) in
  Alcotest.(check some_dur)
    "equal bounds"
    (Some (Duration.ms 100))
    (next_delay (Schedule.jittered ~min:1.0 ~max:1.0 inner) ~step:0);
  Alcotest.(check some_dur)
    "signed zero bounds" (Some Duration.zero)
    (next_delay (Schedule.jittered ~min:(-0.0) ~max:(-0.0) inner) ~step:0);
  let random = (fun seed -> Stdlib.Random.State.make [| seed |]) 17 in
  Alcotest.(check bool)
    "defaults construct" true
    (match next_delay ~random (Schedule.jittered inner) ~step:0 with
    | Some _ -> true
    | None -> false)

let test_jittered_omitted_bounds_match_explicit_defaults () =
  let inner = Schedule.spaced (Duration.ms 100) in
  let delay seed schedule =
    next_delay
      ~random:((fun seed -> Stdlib.Random.State.make [| seed |]) seed)
      schedule ~step:0
  in
  let seed = 17 in
  let explicit = Schedule.jittered ~min:0.8 ~max:1.2 inner in
  let explicit_delay = delay seed explicit in
  Alcotest.(check (option dur))
    "both omitted" explicit_delay
    (delay seed (Schedule.jittered inner));
  Alcotest.(check (option dur))
    "min omitted uses 0.8" explicit_delay
    (delay seed (Schedule.jittered ~max:1.2 inner));
  Alcotest.(check (option dur))
    "max omitted uses 1.2" explicit_delay
    (delay seed (Schedule.jittered ~min:0.8 inner));
  Alcotest.(check bool)
    "omitted min ≠ wrong min 0.0" true
    (delay seed (Schedule.jittered ~max:1.2 inner)
    <> delay seed (Schedule.jittered ~min:0.0 ~max:1.2 inner));
  Alcotest.(check bool)
    "omitted max ≠ wrong max 2.0" true
    (delay seed (Schedule.jittered ~min:0.8 inner)
    <> delay seed (Schedule.jittered ~min:0.8 ~max:2.0 inner))

let test_jittered_construction_does_not_run_pipeline () =
  let calls = ref 0 in
  let inner =
    Schedule.recurs 3
    |> Schedule.while_output (fun output ->
        incr calls;
        output < 10)
  in
  Alcotest.check_raises "nan min skips inner" jitter_min_exn (fun () ->
      ignore (Schedule.jittered ~min:nan ~max:1.0 inner));
  Alcotest.(check int) "callback unused at construction" 0 !calls;
  let random = (fun seed -> Stdlib.Random.State.make [| seed |]) 17 in
  Alcotest.check_raises "nan max skips random" jitter_max_exn (fun () ->
      ignore (Schedule.jittered ~min:0.5 ~max:nan inner));
  let after_reject = Stdlib.Random.State.float random 1.0 in
  let fresh =
    Stdlib.Random.State.float ((fun seed -> Stdlib.Random.State.make [| seed |]) 17) 1.0
  in
  Alcotest.(check (float 0.0)) "construction did not draw" fresh after_reject;
  let valid = Schedule.jittered ~min:1.0 ~max:2.0 inner in
  let random = (fun seed -> Stdlib.Random.State.make [| seed |]) 17 in
  ignore (next_delay ~random valid ~step:0);
  Alcotest.(check bool) "valid step invoked callback" true (!calls > 0);
  let after_step = Stdlib.Random.State.float random 1.0 in
  Alcotest.(check bool) "valid step drew random" true (after_step <> fresh)

let collect_with_now schedule nows =
  let rec loop driver acc = function
    | [] -> List.rev acc
    | now_ms :: rest -> (
        match Schedule.next ~now_ms ~input:() driver with
        | None -> Alcotest.fail "schedule ended"
        | Some (metadata, next) -> loop next (metadata.delay :: acc) rest)
  in
  loop (Schedule.start schedule) [] nows

let test_fixed_uses_cadence_with_now_metadata () =
  let schedule = Schedule.fixed (Duration.ms 5_000) in
  Alcotest.(check (list dur))
    "fixed cadence delays"
    (List.map Duration.ms [ 5_000; 3_500; 0; 3_000 ])
    (collect_with_now schedule [ 0; 6_500; 16_000; 17_000 ])

let test_windowed () =
  let schedule = Schedule.windowed (Duration.ms 10) in
  Alcotest.(check (list dur))
    "window boundary delays"
    (List.map Duration.ms [ 10; 7; 10; 3 ])
    (collect_with_now schedule [ 0; 13; 20; 27 ]);
  let zero = Schedule.windowed Duration.zero in
  List.iter
    (fun step ->
      Alcotest.(check some_dur)
        ("zero step " ^ string_of_int step)
        (Some Duration.zero) (next_delay zero ~step))
    [ 0; 1; 2; 3 ]

let test_schedule_outputs_and_done_decision () =
  let driver = Schedule.start (Schedule.recurs 3) in
  let metadata, driver = next_continue driver in
  Alcotest.(check int) "first output" 0 metadata.output;
  Alcotest.(check int) "first attempt" 1 metadata.attempt;
  let metadata, driver = next_continue driver in
  Alcotest.(check int) "second output" 1 metadata.output;
  let metadata, driver = next_continue driver in
  Alcotest.(check int) "third output" 2 metadata.output;
  match Schedule.step ~now_ms:0 ~input:() driver with
  | Schedule.Done metadata, _ ->
      Alcotest.(check int) "done output" 3 metadata.output;
      Alcotest.(check dur) "done delay" Duration.zero metadata.delay
  | Schedule.Continue _, _ -> Alcotest.fail "expected done decision"

let direct_step ~now_ms ~input (driver : ('input, 'output) Schedule.driver) =
  Schedule.step ~now_ms ~input driver

let test_two_parameter_direct_driver () =
  let driver : (string, int) Schedule.driver = Schedule.start (Schedule.recurs 1) in
  match direct_step ~now_ms:12 ~input:"attempt" driver with
  | Schedule.Continue metadata, _ ->
      Alcotest.(check string) "input" "attempt" metadata.input;
      Alcotest.(check int) "output" 0 metadata.output
  | Schedule.Done _, _ -> Alcotest.fail "expected direct driver to continue"

let test_schedule_elapsed_accumulates_from_first_step () =
  let driver = Schedule.start Schedule.elapsed in
  let metadata, driver = next_continue ~now_ms:100 driver in
  Alcotest.(check dur) "initial elapsed" Duration.zero metadata.output;
  Alcotest.(check int) "start" 100 metadata.start_ms;
  let metadata, driver = next_continue ~now_ms:125 driver in
  Alcotest.(check dur) "second elapsed" (Duration.ms 25) metadata.output;
  Alcotest.(check dur)
    "elapsed since previous" (Duration.ms 25) metadata.elapsed_since_previous;
  let metadata, _ = next_continue ~now_ms:180 driver in
  Alcotest.(check dur) "third elapsed" (Duration.ms 80) metadata.output;
  Alcotest.(check dur)
    "third since previous" (Duration.ms 55) metadata.elapsed_since_previous

let test_schedule_elapsed_signed_origin_saturates () =
  let driver = Schedule.start Schedule.elapsed in
  let metadata, driver = next_continue ~now_ms:min_int driver in
  Alcotest.(check dur) "start elapsed" Duration.zero metadata.elapsed;
  Alcotest.(check dur)
    "start since previous" Duration.zero metadata.elapsed_since_previous;
  Alcotest.(check dur) "start output" Duration.zero metadata.output;
  let metadata, driver = next_continue ~now_ms:0 driver in
  Alcotest.(check dur) "min_int to 0 saturates" (Duration.ms max_int) metadata.elapsed;
  Alcotest.(check dur)
    "since previous saturates" (Duration.ms max_int) metadata.elapsed_since_previous;
  Alcotest.(check dur) "output saturates" (Duration.ms max_int) metadata.output;
  let metadata, driver = next_continue ~now_ms:1 driver in
  Alcotest.(check dur) "total remains max after +1" (Duration.ms max_int) metadata.elapsed;
  Alcotest.(check dur) "previous gap 1" (Duration.ms 1) metadata.elapsed_since_previous;
  let metadata, driver = next_continue ~now_ms:1 driver in
  Alcotest.(check dur)
    "equal previous gap 0" Duration.zero metadata.elapsed_since_previous;
  Alcotest.(check dur) "equal total still max" (Duration.ms max_int) metadata.elapsed;
  let metadata, _ = next_continue ~now_ms:0 driver in
  Alcotest.(check dur)
    "backwards previous gap 0" Duration.zero metadata.elapsed_since_previous;
  Alcotest.(check dur) "backwards total still max" (Duration.ms max_int) metadata.elapsed

let test_schedule_elapsed_exact_limit_and_overrange () =
  let driver = Schedule.start Schedule.elapsed in
  let metadata, driver = next_continue ~now_ms:0 driver in
  Alcotest.(check dur) "origin" Duration.zero metadata.elapsed;
  let metadata, driver = next_continue ~now_ms:max_int driver in
  Alcotest.(check dur) "0 to max_int exact" (Duration.ms max_int) metadata.elapsed;
  Alcotest.(check dur)
    "since previous exact" (Duration.ms max_int) metadata.elapsed_since_previous;
  let driver = Schedule.start Schedule.elapsed in
  let _, driver = next_continue ~now_ms:min_int driver in
  let metadata, _ = next_continue ~now_ms:max_int driver in
  Alcotest.(check dur) "min to max saturates" (Duration.ms max_int) metadata.elapsed

let test_schedule_elapsed_equal_and_backwards_are_zero () =
  let driver = Schedule.start Schedule.elapsed in
  let metadata, driver = next_continue ~now_ms:100 driver in
  Alcotest.(check dur) "first" Duration.zero metadata.elapsed;
  let metadata, driver = next_continue ~now_ms:100 driver in
  Alcotest.(check dur) "equal elapsed" Duration.zero metadata.elapsed;
  Alcotest.(check dur)
    "equal since previous" Duration.zero metadata.elapsed_since_previous;
  let metadata, _ = next_continue ~now_ms:50 driver in
  Alcotest.(check dur) "backwards elapsed" Duration.zero metadata.elapsed;
  Alcotest.(check dur)
    "backwards since previous" Duration.zero metadata.elapsed_since_previous

let test_schedule_during_overrange_is_done () =
  let driver = Schedule.start (Schedule.during (Duration.ms 10)) in
  let metadata, driver = next_continue ~now_ms:min_int driver in
  Alcotest.(check dur) "during start" Duration.zero metadata.output;
  match Schedule.step ~now_ms:0 ~input:() driver with
  | Schedule.Done metadata, _ ->
      Alcotest.(check dur)
        "during overrange elapsed" (Duration.ms max_int) metadata.elapsed;
      Alcotest.(check dur) "during overrange output" (Duration.ms max_int) metadata.output;
      Alcotest.(check dur) "done delay" Duration.zero metadata.delay
  | Schedule.Continue _, _ -> Alcotest.fail "expected During Done"

let test_schedule_windowed_and_fixed_use_saturated_elapsed () =
  let interval = Duration.ms 10 in
  let windowed = Schedule.start (Schedule.windowed interval) in
  let _, windowed = next_continue ~now_ms:min_int windowed in
  let metadata, _ = next_continue ~now_ms:0 windowed in
  Alcotest.(check dur)
    "windowed min_int to 0 elapsed" (Duration.ms max_int) metadata.elapsed;
  let remainder = max_int mod 10 in
  let expected_delay = if remainder = 0 then 10 else 10 - remainder in
  Alcotest.(check dur)
    "windowed delay from max_int mod 10" (Duration.ms expected_delay) metadata.delay;
  let fixed = Schedule.start (Schedule.fixed interval) in
  let first, fixed = next_continue ~now_ms:min_int fixed in
  Alcotest.(check dur) "fixed first delay" interval first.delay;
  let second, _ = next_continue ~now_ms:0 fixed in
  Alcotest.(check dur) "fixed overrange running behind" Duration.zero second.delay;
  Alcotest.(check dur) "fixed overrange elapsed" (Duration.ms max_int) second.elapsed

let test_schedule_during_stops_after_bound () =
  let driver = Schedule.start (Schedule.during (Duration.ms 50)) in
  let metadata, driver = next_continue ~now_ms:0 driver in
  Alcotest.(check dur) "initial output" Duration.zero metadata.output;
  let metadata, driver = next_continue ~now_ms:50 driver in
  Alcotest.(check dur) "boundary still continues" (Duration.ms 50) metadata.output;
  match Schedule.step ~now_ms:51 ~input:() driver with
  | Schedule.Done metadata, _ ->
      Alcotest.(check dur) "done output" (Duration.ms 51) metadata.output
  | Schedule.Continue _, _ -> Alcotest.fail "expected during to stop"

let test_schedule_output_predicates_and_recur_until () =
  let driver =
    Schedule.forever |> Schedule.while_output (fun output -> output < 3) |> Schedule.start
  in
  let metadata, driver = next_continue driver in
  Alcotest.(check int) "while output 0" 0 metadata.output;
  let metadata, driver = next_continue driver in
  Alcotest.(check int) "while output 1" 1 metadata.output;
  let metadata, driver = next_continue driver in
  Alcotest.(check int) "while output 2" 2 metadata.output;
  (match Schedule.step ~now_ms:0 ~input:() driver with
  | Schedule.Done metadata, _ ->
      Alcotest.(check int) "while done output" 3 metadata.output
  | Schedule.Continue _, _ -> Alcotest.fail "expected while_output to stop");
  let driver = Schedule.recur_until (String.equal "stop") |> Schedule.start in
  let metadata, driver = next_continue_with_input ~input:"a" driver in
  Alcotest.(check string) "first input output" "a" metadata.output;
  let metadata, driver = next_continue_with_input ~input:"b" driver in
  Alcotest.(check string) "second input output" "b" metadata.output;
  match Schedule.step ~now_ms:0 ~input:"stop" driver with
  | Schedule.Done metadata, _ ->
      Alcotest.(check string) "stop output" "stop" metadata.output
  | Schedule.Continue _, _ -> Alcotest.fail "expected recur_until to stop"

let test_schedule_modify_delay () =
  let schedule =
    Schedule.spaced (Duration.ms 10)
    |> Schedule.modify_delay (fun output delay ->
        Duration.ms (Duration.to_ms delay + output))
  in
  let driver = Schedule.start schedule in
  let metadata, driver = next_continue driver in
  Alcotest.(check dur) "first modified delay" (Duration.ms 10) metadata.delay;
  let metadata, _ = next_continue driver in
  Alcotest.(check dur) "second modified delay" (Duration.ms 11) metadata.delay

let test_fibonacci () =
  let schedule = Schedule.fibonacci (dur_ms 10) in
  let rec collect driver remaining acc =
    if remaining = 0 then List.rev acc
    else
      match Schedule.next ~now_ms:0 ~input:() driver with
      | None -> Alcotest.fail "fibonacci schedule ended"
      | Some (metadata, next) -> collect next (remaining - 1) (metadata.delay :: acc)
  in
  Alcotest.(check (list dur))
    "first fibonacci delays"
    (List.map dur_ms [ 10; 10; 20; 30; 50; 80; 130; 210 ])
    (collect (Schedule.start schedule) 8 [])

let test_fibonacci_composes_with_recurs_driver () =
  let schedule = Schedule.both (Schedule.recurs 6) (Schedule.fibonacci (Duration.ms 5)) in
  let rec collect driver acc =
    match Schedule.next ~now_ms:0 ~input:() driver with
    | None -> List.rev acc
    | Some (metadata, next) -> collect next (metadata.delay :: acc)
  in
  Alcotest.(check (list dur))
    "recurs limits fibonacci driver"
    (List.map Duration.ms [ 5; 5; 10; 15; 25; 40 ])
    (collect (Schedule.start schedule) [])

let test_schedule_composition_outputs () =
  let driver =
    Schedule.both (Schedule.recurs 2) (Schedule.fibonacci (Duration.ms 5))
    |> Schedule.start
  in
  let metadata, driver = next_continue driver in
  Alcotest.(check (pair int dur)) "first output" (0, Duration.ms 5) metadata.output;
  let metadata, driver = next_continue driver in
  Alcotest.(check (pair int dur)) "second output" (1, Duration.ms 5) metadata.output;
  match Schedule.step ~now_ms:0 ~input:() driver with
  | Schedule.Done metadata, _ ->
      Alcotest.(check (pair int dur)) "done output" (2, Duration.ms 10) metadata.output
  | Schedule.Continue _, _ -> Alcotest.fail "expected composed schedule to stop"

let test_fibonacci_edges () =
  let zero = Schedule.fibonacci Duration.zero in
  List.iter
    (fun step ->
      Alcotest.(check some_dur)
        ("zero step " ^ string_of_int step)
        (Some Duration.zero) (next_delay zero ~step))
    [ 0; 1; 2; 3 ];
  let base = Duration.ms ((max_int / 2) + 1) in
  let driver = Schedule.start (Schedule.fibonacci base) in
  let driver =
    match Schedule.next ~now_ms:0 ~input:() driver with
    | Some (metadata, next) ->
        Alcotest.(check dur) "first delay" base metadata.delay;
        next
    | None -> Alcotest.fail "fibonacci schedule ended before first delay"
  in
  let driver =
    match Schedule.next ~now_ms:0 ~input:() driver with
    | Some (metadata, next) ->
        Alcotest.(check dur) "second delay" base metadata.delay;
        next
    | None -> Alcotest.fail "fibonacci schedule ended before second delay"
  in
  match Schedule.next ~now_ms:0 ~input:() driver with
  | Some (metadata, _) ->
      Alcotest.(check dur) "third delay saturates" (Duration.ms max_int) metadata.delay
  | None -> Alcotest.fail "fibonacci schedule ended on overflow"

let test_schedule_linear_saturates_on_overflow () =
  let driver =
    Schedule.start (Schedule.linear ~initial:(Duration.ms 1) ~step:(Duration.ms max_int))
  in
  let driver =
    match Schedule.next ~now_ms:0 ~input:() driver with
    | Some (metadata, next) ->
        Alcotest.(check dur) "first delay" (Duration.ms 1) metadata.delay;
        next
    | None -> Alcotest.fail "linear schedule ended too early"
  in
  match Schedule.next ~now_ms:0 ~input:() driver with
  | Some (metadata, _) ->
      Alcotest.(check dur) "second delay saturates" (Duration.ms max_int) metadata.delay
  | None -> Alcotest.fail "linear schedule ended on overflow"

let test_spaced_fixed_linear () =
  Alcotest.(check some_dur)
    "spaced"
    (Some (Duration.seconds 1))
    (next_delay (Schedule.spaced (Duration.seconds 1)) ~step:4);
  Alcotest.(check some_dur)
    "fixed"
    (Some (Duration.seconds 1))
    (next_delay (Schedule.fixed (Duration.seconds 1)) ~step:4);
  Alcotest.(check some_dur)
    "linear step 3"
    (Some (Duration.seconds 7))
    (next_delay
       (Schedule.linear ~initial:(Duration.seconds 1) ~step:(Duration.seconds 2))
       ~step:3)

let test_schedule_composition () =
  Alcotest.(check some_dur)
    "both takes max"
    (Some (Duration.seconds 2))
    (next_delay
       (Schedule.both
          (Schedule.spaced (Duration.seconds 1))
          (Schedule.spaced (Duration.seconds 2)))
       ~step:0);
  Alcotest.(check some_dur)
    "either takes min"
    (Some (Duration.seconds 1))
    (next_delay
       (Schedule.either
          (Schedule.spaced (Duration.seconds 1))
          (Schedule.spaced (Duration.seconds 2)))
       ~step:0);
  Alcotest.(check some_dur)
    "and_then falls through"
    (Some (Duration.seconds 1))
    (next_delay
       (Schedule.and_then (Schedule.recurs 1) (Schedule.spaced (Duration.seconds 1)))
       ~step:1)

let test_schedule_composition_termination_with_driver () =
  let collect schedule =
    let rec loop driver acc =
      match Schedule.next ~now_ms:0 ~input:() driver with
      | None -> List.rev acc
      | Some (metadata, next) -> loop next (metadata.delay :: acc)
    in
    loop (Schedule.start schedule) []
  in
  Alcotest.(check (list dur))
    "both terminates with shorter side"
    [ Duration.seconds 2; Duration.seconds 2 ]
    (collect
       (Schedule.both
          (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.seconds 1)))
          (Schedule.spaced (Duration.seconds 2))));
  Alcotest.(check (list dur))
    "either terminates with longer side"
    [ Duration.seconds 1; Duration.seconds 1; Duration.seconds 2 ]
    (collect
       (Schedule.either
          (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.seconds 1)))
          (Schedule.both (Schedule.recurs 3) (Schedule.spaced (Duration.seconds 2)))));
  Alcotest.(check (list dur))
    "and_then runs second phase after first"
    [ Duration.zero; Duration.seconds 1; Duration.seconds 1 ]
    (collect
       (Schedule.and_then (Schedule.recurs 1)
          (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.seconds 1)))))

let test_schedule_and_then_offsets_second_phase () =
  let exponential =
    Schedule.and_then (Schedule.recurs 5)
      (Schedule.exponential ~factor:2.0 (Duration.seconds 1))
  in
  List.iter
    (fun step ->
      Alcotest.(check some_dur)
        ("exponential warmup " ^ string_of_int step)
        (Some Duration.zero)
        (next_delay exponential ~step))
    [ 0; 1; 2; 3; 4 ];
  Alcotest.(check some_dur)
    "exponential phase step 0"
    (Some (Duration.seconds 1))
    (next_delay exponential ~step:5);
  Alcotest.(check some_dur)
    "exponential phase step 1"
    (Some (Duration.seconds 2))
    (next_delay exponential ~step:6);
  Alcotest.(check some_dur)
    "exponential phase step 2"
    (Some (Duration.seconds 4))
    (next_delay exponential ~step:7);
  let linear =
    Schedule.and_then (Schedule.recurs 3)
      (Schedule.linear ~initial:(Duration.ms 100) ~step:(Duration.ms 50))
  in
  Alcotest.(check some_dur)
    "linear phase step 0"
    (Some (Duration.ms 100))
    (next_delay linear ~step:3);
  Alcotest.(check some_dur)
    "linear phase step 1"
    (Some (Duration.ms 150))
    (next_delay linear ~step:4);
  let jittered =
    Schedule.and_then (Schedule.recurs 2)
      (Schedule.exponential ~factor:2.0 (Duration.ms 100))
    |> Schedule.jittered ~min:1.0 ~max:1.0
  in
  Alcotest.(check some_dur)
    "jittered wraps second phase step 0"
    (Some (Duration.ms 100))
    (next_delay jittered ~step:2)

let test_schedule_jittered_stays_inside_multiplier_bounds () =
  let schedule =
    Schedule.spaced (Duration.ms 100) |> Schedule.jittered ~min:0.5 ~max:1.5
  in
  let driver =
    ref
      (Schedule.start
         ~random:((fun seed -> Stdlib.Random.State.make [| seed |]) 23)
         schedule)
  in
  for step = 0 to 99 do
    match Schedule.next ~now_ms:0 ~input:() !driver with
    | None -> Alcotest.fail "jittered spaced schedule terminated"
    | Some (metadata, next) ->
        driver := next;
        Alcotest.(check bool)
          ("step " ^ string_of_int step ^ " inside lower bound")
          true
          (Duration.compare metadata.delay (Duration.ms 50) >= 0);
        Alcotest.(check bool)
          ("step " ^ string_of_int step ^ " inside upper bound")
          true
          (Duration.compare metadata.delay (Duration.ms 150) <= 0)
  done

let test_schedule_jittered_exponential_does_not_raise () =
  let schedule =
    Schedule.(jittered ~min:1.1 ~max:1.2 (exponential ~factor:2.0 (Duration.seconds 1)))
  in
  let driver =
    ref
      (Schedule.start
         ~random:((fun seed -> Stdlib.Random.State.make [| seed |]) 7)
         schedule)
  in
  for _ = 1 to 80 do
    match Schedule.next ~now_ms:0 ~input:() !driver with
    | Some (_, next_driver) -> driver := next_driver
    | None -> ()
  done;
  Alcotest.(check bool) "advancing the schedule never raised" true true

let test_schedule_jittered_uses_explicit_random () =
  let schedule = Schedule.jittered (Schedule.spaced (Duration.ms 100)) in
  let seed () = Stdlib.Random.State.make [| 17 |] in
  Alcotest.(check some_dur)
    "seed repeatable"
    (next_delay ~random:(seed ()) schedule ~step:0)
    (next_delay ~random:(seed ()) schedule ~step:0)

let tests =
  [
    ( "Duration and Schedule ncore-fjud ncore-aqu8 ncore-n04u",
      [
        Alcotest.test_case "test_duration_constructors ncore-fjud" `Quick
          test_duration_constructors;
        Alcotest.test_case "test_duration_ordering ncore-fjud" `Quick
          test_duration_ordering;
        Alcotest.test_case "test_duration_algebra ncore-fjud" `Quick test_duration_algebra;
        Alcotest.test_case "test_duration_scale_identity_at_max ncore-fjud" `Quick
          test_duration_scale_identity_at_max;
        Alcotest.test_case "test_duration_overflow ncore-fjud" `Quick
          test_duration_overflow;
        Alcotest.test_case "test_duration_min_max_clamp ncore-fjud" `Quick
          test_duration_min_max_clamp;
        Alcotest.test_case "test_duration_zero_detection_and_conversion ncore-fjud" `Quick
          test_duration_zero_detection_and_conversion;
        Alcotest.test_case "test_duration_humanize ncore-fjud" `Quick
          test_duration_humanize;
        Alcotest.test_case "test_recurs ncore-fjud" `Quick test_recurs;
        Alcotest.test_case "test_recurs_driver_yields_exactly_n_delays ncore-fjud" `Quick
          test_recurs_driver_yields_exactly_n_delays;
        Alcotest.test_case "test_recurs_rejects_max_int_at_construction ncore-fjud" `Quick
          test_recurs_rejects_max_int_at_construction;
        Alcotest.test_case
          "test_recurs_accepts_max_int_minus_one_at_construction ncore-fjud" `Quick
          test_recurs_accepts_max_int_minus_one_at_construction;
        Alcotest.test_case
          "test_recurs_negative_matches_zero_terminal_and_replay ncore-fjud" `Quick
          test_recurs_negative_matches_zero_terminal_and_replay;
        Alcotest.test_case "test_exponential ncore-fjud" `Quick test_exponential;
        Alcotest.test_case "test_exponential_omitted_factor_defaults_to_two ncore-fjud"
          `Quick test_exponential_omitted_factor_defaults_to_two;
        Alcotest.test_case "test_exponential_saturates_on_overflow ncore-fjud" `Quick
          test_exponential_saturates_on_overflow;
        Alcotest.test_case "test_exponential_zero_survives_max_float_power ncore-fjud"
          `Quick test_exponential_zero_survives_max_float_power;
        Alcotest.test_case "test_exponential_positive_base_saturates_max_float ncore-fjud"
          `Quick test_exponential_positive_base_saturates_max_float;
        Alcotest.test_case "test_exponential_zero_base_factors ncore-fjud" `Quick
          test_exponential_zero_base_factors;
        Alcotest.test_case
          "test_exponential_rejects_invalid_factor_at_construction ncore-fjud" `Quick
          test_exponential_rejects_invalid_factor_at_construction;
        Alcotest.test_case
          "test_exponential_accepts_zero_signed_zero_unit_decay ncore-fjud" `Quick
          test_exponential_accepts_zero_signed_zero_unit_decay;
        Alcotest.test_case
          "test_jittered_rejects_invalid_bounds_at_construction ncore-fjud" `Quick
          test_jittered_rejects_invalid_bounds_at_construction;
        Alcotest.test_case
          "test_jittered_accepts_equal_signed_zero_and_defaults ncore-fjud" `Quick
          test_jittered_accepts_equal_signed_zero_and_defaults;
        Alcotest.test_case
          "test_jittered_omitted_bounds_match_explicit_defaults ncore-fjud" `Quick
          test_jittered_omitted_bounds_match_explicit_defaults;
        Alcotest.test_case "test_jittered_construction_does_not_run_pipeline ncore-fjud"
          `Quick test_jittered_construction_does_not_run_pipeline;
        Alcotest.test_case "test_fixed_uses_cadence_with_now_metadata ncore-fjud" `Quick
          test_fixed_uses_cadence_with_now_metadata;
        Alcotest.test_case "test_windowed ncore-fjud" `Quick test_windowed;
        Alcotest.test_case "test_schedule_outputs_and_done_decision ncore-fjud" `Quick
          test_schedule_outputs_and_done_decision;
        Alcotest.test_case "test_two_parameter_direct_driver ncore-fjud" `Quick
          test_two_parameter_direct_driver;
        Alcotest.test_case "test_schedule_elapsed_accumulates_from_first_step ncore-fjud"
          `Quick test_schedule_elapsed_accumulates_from_first_step;
        Alcotest.test_case "test_schedule_elapsed_signed_origin_saturates ncore-fjud"
          `Quick test_schedule_elapsed_signed_origin_saturates;
        Alcotest.test_case "test_schedule_elapsed_exact_limit_and_overrange ncore-fjud"
          `Quick test_schedule_elapsed_exact_limit_and_overrange;
        Alcotest.test_case "test_schedule_elapsed_equal_and_backwards_are_zero ncore-fjud"
          `Quick test_schedule_elapsed_equal_and_backwards_are_zero;
        Alcotest.test_case "test_schedule_during_overrange_is_done ncore-fjud" `Quick
          test_schedule_during_overrange_is_done;
        Alcotest.test_case
          "test_schedule_windowed_and_fixed_use_saturated_elapsed ncore-fjud" `Quick
          test_schedule_windowed_and_fixed_use_saturated_elapsed;
        Alcotest.test_case "test_schedule_during_stops_after_bound ncore-fjud" `Quick
          test_schedule_during_stops_after_bound;
        Alcotest.test_case "test_schedule_output_predicates_and_recur_until ncore-fjud"
          `Quick test_schedule_output_predicates_and_recur_until;
        Alcotest.test_case "test_schedule_modify_delay ncore-fjud" `Quick
          test_schedule_modify_delay;
        Alcotest.test_case "test_fibonacci ncore-fjud" `Quick test_fibonacci;
        Alcotest.test_case "test_fibonacci_composes_with_recurs_driver ncore-fjud" `Quick
          test_fibonacci_composes_with_recurs_driver;
        Alcotest.test_case "test_schedule_composition_outputs ncore-fjud" `Quick
          test_schedule_composition_outputs;
        Alcotest.test_case "test_fibonacci_edges ncore-fjud" `Quick test_fibonacci_edges;
        Alcotest.test_case "test_schedule_linear_saturates_on_overflow ncore-fjud" `Quick
          test_schedule_linear_saturates_on_overflow;
        Alcotest.test_case "test_spaced_fixed_linear ncore-fjud" `Quick
          test_spaced_fixed_linear;
        Alcotest.test_case "test_schedule_composition ncore-fjud" `Quick
          test_schedule_composition;
        Alcotest.test_case "test_schedule_composition_termination_with_driver ncore-fjud"
          `Quick test_schedule_composition_termination_with_driver;
        Alcotest.test_case "test_schedule_and_then_offsets_second_phase ncore-fjud" `Quick
          test_schedule_and_then_offsets_second_phase;
        Alcotest.test_case
          "test_schedule_jittered_stays_inside_multiplier_bounds ncore-fjud" `Quick
          test_schedule_jittered_stays_inside_multiplier_bounds;
        Alcotest.test_case "test_schedule_jittered_exponential_does_not_raise ncore-fjud"
          `Quick test_schedule_jittered_exponential_does_not_raise;
        Alcotest.test_case "test_schedule_jittered_uses_explicit_random ncore-fjud" `Quick
          test_schedule_jittered_uses_explicit_random;
      ] );
  ]
