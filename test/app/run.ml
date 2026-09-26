(* Story IDs covered: ^napp-3j07 ^napp-78pf ^napp-f7d6 ^napp-qg7n
   ^napp-pn0a ^napp-kq3b ^napp-2aa6 ^napp-yplu ^napp-tuvw
   ^napp-svkp ^napp-o6d6 ^napp-mbpr ^napp-433c ^napp-fu4q
   ^nfix-j678. *)
open Eta_app

let check_int = Alcotest.(check int)
let check_string = Alcotest.(check string)

let contains hay needle =
  let rec go i =
    i + String.length needle <= String.length hay
    && (String.sub hay i (String.length needle) = needle || go (i + 1))
  in
  go 0

let expect_part where needle = Alcotest.(check bool) needle true (contains where needle)

type models = { api_key : string }
type settings = { models : models; port : int }

let models_schema =
  Eta_schema.(
    record1 ~name:"models"
      (fun api_key -> { api_key })
      (required ~secret:true ~env:"OPENROUTER_API_KEY" "api_key" string (fun m ->
           m.api_key))
      ~equal:( = ) ())

let schema =
  Eta_schema.(
    record2 ~name:"settings"
      (fun models port -> { models; port })
      (required "models" models_schema (fun c -> c.models))
      (required ~env:"PORT" "port" int (fun c -> c.port))
      ~equal:( = ) ())

let good = "port = 42\n[models]\napi_key = \"file-secret\"\n"
let getenv = function "HOME" -> Some "/home/demo" | _ -> None
let pp_err fmt = function `Problem message -> Format.pp_print_string fmt message

let run ?(argv = [| "demo" |]) ?(text = good) ?(envvars = getenv) ?on_switch
    ?(read_path = fun _ -> ()) ?(program = fun _ _ _ -> Ok ()) () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let output = Buffer.create 80 and errors = Buffer.create 80 in
      let memory = Eta_observability.Logger.Memory.create () in
      let code =
        run_for_test ?on_switch ~env ~name:"demo" ~config:schema ~pp_err
          ~journal:(Eta_observability.Logger.Memory.reporter memory)
          ~getenv:envvars
          ~read:(fun path ->
            read_path path;
            Ok text)
          ~stderr:(fun text -> Buffer.add_string errors text)
          ~stdout:(fun text -> Buffer.add_string output text)
          ~argv program
      in
      (code, Buffer.contents output, Buffer.contents errors, memory))

let test_clean () =
  let started = ref false in
  let program env config _ =
    started := true;
    check_int "config" 42 config.port;
    Eta_observability.Logger.info env.Env.logger "started";
    Ok ()
  in
  let code, _, err, logs = run ~program () in
  check_int "^napp-3j07 root scope exits clean" 0 code;
  check_string "no diagnostics" "" err;
  Alcotest.(check int)
    "^napp-mbpr journal logger created" 1
    (List.length (Eta_observability.Logger.Memory.records logs));
  Alcotest.(check bool) "^napp-o6d6 env passed" true !started

let test_failures () =
  let code, _, err, _ = run ~program:(fun _ _ _ -> Error (`Problem "typed example")) () in
  check_int "^napp-f7d6 typed" 1 code;
  expect_part err "typed example";
  let code, _, err, _ = run ~program:(fun _ _ _ -> failwith "defect example") () in
  check_int "^napp-f7d6 defect" 2 code;
  expect_part err "defect example";
  let code, _, err, _ =
    run
      ~program:(fun _ _ sw ->
        Eio.Switch.on_release sw (fun () -> failwith "release example");
        Error (`Problem "primary example"))
      ()
  in
  check_int "^napp-f7d6 composite" 2 code;
  expect_part err "primary example";
  expect_part err "release example"

module First :
  SERVICE
    with type t = int ref
     and type config = unit
     and type deps = string list ref
     and type error = [ `Problem of string ] = struct
  type t = int ref
  type config = unit
  type deps = string list ref
  type error = [ `Problem of string ]

  let create ~sw () events =
    events := !events @ [ "first" ];
    Eio.Switch.on_release sw (fun () -> events := !events @ [ "release-first" ]);
    Ok (ref 1)

  let status t = Status.make ~details:[ ("counter", string_of_int !t) ] "first" Status.Ok
end

module Second :
  SERVICE
    with type t = int ref
     and type config = unit
     and type deps = int ref * string list ref
     and type error = [ `Problem of string ] = struct
  type t = int ref
  type config = unit
  type deps = int ref * string list ref
  type error = [ `Problem of string ]

  let create ~sw () (first, events) =
    events := !events @ [ "second" ];
    Eio.Switch.on_release sw (fun () -> events := !events @ [ "release-second" ]);
    Ok first

  let status t = Status.make "second" (Status.Degraded (string_of_int !t))
end

let ( let* ) = Result.bind

let state_name = function
  | Status.Ok -> "ok"
  | Status.Degraded detail -> "degraded:" ^ detail
  | Status.Failed detail -> "failed:" ^ detail

let render status = status.Status.name ^ ":" ^ state_name status.Status.state

module Reporter :
  SERVICE
    with type t = unit -> Status.t list
     and type config = unit
     and type deps = unit -> Status.t list
     and type error = [ `Problem of string ] = struct
  type t = unit -> Status.t list
  type config = unit
  type deps = unit -> Status.t list
  type error = [ `Problem of string ]

  let create ~sw:_ () query = Ok query

  let status query =
    let seen = List.map (fun status -> status.Status.name) (query ()) in
    Status.make ~details:[ ("seen", String.concat "," seen) ] "reporter" Status.Ok
end

let test_status_query_before_serve () =
  let events = ref [] in
  let id = Eta.Interrupt_id.create () in
  let live = ref [] and counter = ref "" and seen = ref "" and reporter = ref "" in
  let status_count = ref 0 in
  let program _ _ sw =
    let open Result in
    let* first = First.create ~sw () events in
    let* second = Second.create ~sw () (first, events) in
    let query =
      status_query [ (fun () -> First.status first); (fun () -> Second.status second) ]
    in
    let* reporter_service = Reporter.create ~sw () query in
    Eio.Fiber.fork_daemon ~sw (fun () ->
        Eio.Fiber.yield ();
        first := 9;
        let statuses = query () in
        status_count := List.length statuses;
        live := List.map render statuses;
        (counter :=
           match List.find_opt (fun status -> status.Status.name = "first") statuses with
           | Some status -> List.assoc "counter" status.Status.details
           | None -> "");
        let reporter_status = Reporter.status reporter_service in
        reporter := render reporter_status;
        seen := List.assoc "seen" reporter_status.Status.details;
        request_stop ~sw id;
        `Stop_daemon);
    serve ~sw ()
  in
  let code, _, err, _ = run ~program () in
  check_int "^napp-78pf signal path exits zero" 0 code;
  check_string "clean stop silent" "" err;
  Alcotest.(check (list string))
    "^napp-78pf reverse release ^napp-qg7n two services"
    [ "first"; "second"; "release-second"; "release-first" ]
    !events;
  Alcotest.(check int) "^napp-433c complete program in-process" 2 !status_count;
  Alcotest.(check (list string))
    "^napp-kq3b live status read inside serve"
    [ "first:ok"; "second:degraded:9" ]
    !live;
  check_string "^napp-pn0a details" "9" !counter;
  check_string "^nfix-j678 service created before serve answers from its query"
    "reporter:ok" !reporter;
  check_string "^nfix-j678 its query is the composed one" "first,second" !seen

let test_daemon_stop () =
  let stop_id = Eta.Interrupt_id.create () in
  let code, _, err, _ =
    run
      ~on_switch:(fun sw ->
        Eio.Fiber.fork_daemon ~sw (fun () ->
            request_stop ~sw stop_id;
            `Stop_daemon))
      ~program:(fun _ _ sw -> serve ~sw ())
      ()
  in
  check_int "^napp-78pf child fiber stop ID is recognized" 0 code;
  check_string "clean child stop silent" "" err

let test_config () =
  let seen = ref "" in
  let code, _, _, _ = run ~read_path:(fun path -> seen := path) () in
  check_int "^napp-2aa6 config path" 0 code;
  check_string "XDG fallback" "/home/demo/.config/demo/config.toml" !seen;
  let code, _, _, _ =
    run
      ~argv:[| "demo"; "--config"; "override.toml" |]
      ~read_path:(fun path -> seen := path)
      ()
  in
  check_int "--config accepted" 0 code;
  check_string "CLI precedence" "override.toml" !seen;
  let code, _, _, _ =
    run
      ~envvars:(function "XDG_CONFIG_HOME" -> Some "/xdg" | _ -> None)
      ~read_path:(fun path -> seen := path)
      ()
  in
  check_int "XDG" 0 code;
  check_string "XDG path" "/xdg/demo/config.toml" !seen

let test_validation () =
  let cases =
    [
      ("unknown", good ^ "surprise = 1\n", "/models/surprise");
      ("missing", "port = 1\n[models]\n", "/models/api_key");
      ("wrong", "port = \"bad\"\n[models]\napi_key = \"a\"\n", "/port");
    ]
  in
  List.iter
    (fun (name, text, pointer) ->
      let started = ref false in
      let code, _, err, _ =
        run ~text
          ~program:(fun _ _ _ ->
            started := true;
            Ok ())
          ()
      in
      check_int ("^napp-yplu " ^ name) 2 code;
      expect_part err pointer;
      Alcotest.(check bool) "never starts" false !started)
    cases

let test_check_and_env () =
  let envvars = function
    | "OPENROUTER_API_KEY" -> Some "override-secret"
    | "HOME" -> Some "/home/demo"
    | "PORT" -> Some "73"
    | _ -> None
  in
  let code, out, err, _ =
    run
      ~argv:[| "demo"; "config"; "check" |]
      ~envvars
      ~program:(fun _ _ _ -> failwith "must not start")
      ()
  in
  check_int "^napp-svkp check" 0 code;
  check_string "no error" "" err;
  expect_part out "<redacted>";
  Alcotest.(check bool)
    "^napp-svkp no secret output" false
    (contains out "override-secret");
  let found = ref "" and parsed_port = ref 0 in
  let code, _, _, _ =
    run ~envvars ~text:"port = 3\n[models]\n"
      ~program:(fun _ cfg _ ->
        found := cfg.models.api_key;
        parsed_port := cfg.port;
        Ok ())
      ()
  in
  check_int "^napp-tuvw env fills missing required" 0 code;
  check_string "env overrides" "override-secret" !found;
  check_int "numeric env override" 73 !parsed_port;
  let code, _, err, _ = run ~text:"port = 3\n" ~argv:[| "demo"; "config"; "check" |] () in
  check_int "^napp-svkp invalid check" 2 code;
  expect_part err "/models"

let test_cli_hook () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let calls = ref 0 in
      let hook =
        Cmdliner.Cmd.v (Cmdliner.Cmd.info "ping")
          Cmdliner.Term.(
            const (fun () ->
                incr calls;
                7))
      in
      let code =
        run_for_test ~commands:[ hook ] ~env ~name:"demo" ~config:schema ~pp_err
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~getenv
          ~read:(fun _ -> failwith "hook must not load config")
          ~stderr:ignore ~stdout:ignore ~argv:[| "demo"; "ping" |]
          (fun _ _ _ -> failwith "hook must not start program")
      in
      check_int "^napp-3j07 consumer subcommand" 7 code;
      check_int "hook invoked" 1 !calls)

let test_foreign_interruption () =
  let foreign = Eta.Interrupt_id.create () in
  let code, _, err, _ =
    run
      ~program:(fun _ _ sw ->
        Eio.Switch.fail sw (Eio.Cancel.Cancelled (Eta.Interrupt_id.stop foreign));
        Eio.Fiber.await_cancel ())
      ()
  in
  check_int "^napp-f7d6 foreign interruption is not a signal stop" 2 code;
  Alcotest.(check bool) "foreign interruption rendered" true (String.length err > 0);
  let code, _, err, _ =
    run
      ~program:(fun _ _ sw ->
        Eio.Switch.fail sw (Eio.Cancel.Cancelled (Failure "unknown stop"));
        Eio.Fiber.await_cancel ())
      ()
  in
  check_int "^napp-f7d6 anonymous interruption is not a signal stop" 2 code;
  Alcotest.(check bool) "anonymous interruption rendered" true (String.length err > 0)

let test_cli_and_io_errors () =
  let code, out, _, _ = run ~argv:[| "demo"; "--help" |] () in
  check_int "^napp-3j07 help" 0 code;
  expect_part out "config";
  let code, _, err, _ = run ~argv:[| "demo"; "config"; "nope" |] () in
  check_int "^napp-f7d6 bad command" 2 code;
  expect_part err "nope";
  let code, _, err, _ = run ~text:"[models\n" () in
  check_int "^napp-yplu malformed TOML" 2 code;
  expect_part err "TOML line";
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let err = Buffer.create 32 in
      let code =
        run_for_test ~env ~name:"demo" ~config:schema ~pp_err
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~getenv
          ~read:(fun _ -> Error "no such file")
          ~stderr:(fun text -> Buffer.add_string err text)
          ~stdout:ignore ~argv:[| "demo" |]
          (fun _ _ _ -> failwith "must not start")
      in
      check_int "^napp-2aa6 unreadable config" 2 code;
      expect_part (Buffer.contents err) "no such file")

(* nlimit-s3f4: real SIGTERM and SIGINT travel through the Door. *)
let test_real_signal signo () =
  let config_path = Filename.temp_file "eta-app-signal-" ".toml" in
  Fun.protect
    ~finally:(fun () -> Sys.remove config_path)
    (fun () ->
      let output = open_out config_path in
      output_string output "port = 42\n";
      close_out output;
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let fixture =
                Filename.concat
                  (Filename.dirname Sys.executable_name)
                  "signal_fixture.exe"
              in
              let child =
                match
                  Eta_process.Child.spawn ~sw ~clock:env#clock ~mgr:env#process_mgr
                    ~argv:[ fixture; "--config"; config_path ]
                    ~grace:(Eta.Duration.ms 50) ~stdout:Eta_process.Child.Pipe
                    ~stderr:Eta_process.Child.Pipe ~fds:[] ()
                with
                | Ok child -> child
                | Error _ -> Alcotest.fail "invalid signal fixture spawn"
              in
              let source = Option.get (Eta_process.Child.stdout child) in
              let ready =
                Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                    Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:1024 source))
              in
              check_string "Door ready" "ready" ready;
              Eta_process.Child.signal child signo;
              let status =
                Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                    Eta_process.Child.await child)
              in
              Alcotest.(check bool)
                "signal maps to exit code zero" true
                (match status with Eta_process.Child.Exited 0 -> true | _ -> false);
              Eta_process.Child.signal child signo;
              ignore (Eta_process.Child.stop child);
              let journal =
                Eio.Flow.read_all (Option.get (Eta_process.Child.stderr child))
              in
              expect_part journal "\"msg\":\"signal stopped\"")))

let () =
  Alcotest.run "eta_app"
    [
      ( "door",
        [
          Alcotest.test_case "^napp-3j07 ^napp-o6d6 ^napp-mbpr clean door" `Quick
            test_clean;
          Alcotest.test_case "^napp-f7d6 typed defect composite" `Quick test_failures;
          Alcotest.test_case "^napp-f7d6 foreign interruption" `Quick
            test_foreign_interruption;
          Alcotest.test_case
            "^napp-78pf ^napp-qg7n ^napp-pn0a ^napp-kq3b ^napp-433c ^nfix-j678" `Quick
            test_status_query_before_serve;
          Alcotest.test_case "^napp-78pf child fiber stop" `Quick test_daemon_stop;
          Alcotest.test_case "^napp-2aa6 path precedence" `Quick test_config;
          Alcotest.test_case "^napp-yplu validation pointers" `Quick test_validation;
          Alcotest.test_case "^napp-tuvw ^napp-svkp env and check" `Quick
            test_check_and_env;
          Alcotest.test_case "^napp-3j07 command hook ^napp-fu4q deps" `Quick
            test_cli_hook;
          Alcotest.test_case "^napp-2aa6 ^napp-yplu CLI and IO errors" `Quick
            test_cli_and_io_errors;
          Alcotest.test_case "nlimit-s3f4 real SIGTERM" `Quick
            (test_real_signal Sys.sigterm);
          Alcotest.test_case "nlimit-s3f4 real SIGINT" `Quick
            (test_real_signal Sys.sigint);
        ] );
    ]
