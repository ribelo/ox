open Ox
let diagnose ~kind:_ _ = ()
let pp_err fmt _ = Format.pp_print_string fmt "typed"
let code ?(requested = []) ?(interrupt_exit = 0) ?(typed_exit = 1) outcome =
  Door_mapping.render ~stop_ids:(ref requested) ~interrupt_exit
    ~exit_code:(fun _ -> typed_exit) ~defect_exit:2 ~success:(fun () -> 0)
    diagnose pp_err outcome
let checks = ref 0
let test name actual wanted =
  if actual <> wanted then failwith (Printf.sprintf "%s: %d expected %d" name actual wanted);
  incr checks; Printf.printf "PASS %s = %d\n%!" name actual
let () = Eio_main.run (fun env ->
  Printf.printf "BACKEND %s\n%!" (Eio.Stdenv.backend_id env);
  test "success" (code (Exit.Success ())) 0;
  test "proposed propagated Canceled" (code (Exit.Failure (Cause.Fail `Canceled))) 1;
  test "custom typed exit" (code ~typed_exit:7 (Exit.Failure (Cause.Fail `Canceled))) 7;
  let timeout = Scope.run (fun _ -> Timeout.timeout ~clock:env#clock (Duration.ms 1) Eio.Fiber.await_cancel) in
  test "existing Timeout" (code timeout) 1;
  let requested = ref [] in
  let id = Interrupt_id.create () in
  let stop = Scope.run (fun sw -> Eio.Fiber.with_binding Door_mapping.stop_ids requested (fun () ->
    Door_mapping.request_stop ~sw id; Eio.Fiber.await_cancel ())) in
  test "actual request_stop service/run_owned" (code ~requested:!requested stop) 0;
  test "actual request_stop run_owned_code" (code ~requested:!requested ~interrupt_exit:130 stop) 130;
  test "same id without Door provenance" (code stop) 2;
  let foreign = Scope.run (fun sw -> Eio.Switch.fail sw (Eio.Cancel.Cancelled (Failure "foreign")); Eio.Fiber.await_cancel ()) in
  test "foreign anonymous interruption" (code foreign) 2;
  let boom = Failure "defect" in
  test "defect" (code (Scope.run (fun _ -> raise boom))) 2;
  let cleanup = Scope.run (fun sw -> Eio.Switch.on_release sw (fun () -> failwith "cleanup"); Error `Canceled) in
  test "Canceled plus cleanup defect" (code cleanup) 2;
  let race = Scope.run (fun sw -> Concurrent.race ~sw [ (fun () -> Error `Canceled); (fun () -> Ok ()) ]) in
  test "race success" (code race) 0;
  let all_canceled = Scope.run (fun sw -> Concurrent.race ~sw [ (fun () -> Error `Canceled); (fun () -> Error `Canceled) ]) in
  test "all-failed race returned as typed error" (code all_canceled) 1;
  Printf.printf "RESULT %d/%d extracted Door mapper checks passed\n%!" !checks !checks)
