(* Story IDs covered: ^napp-3j07 ^napp-78pf ^napp-f7d6 ^napp-qg7n
   ^napp-pn0a ^napp-kq3b ^napp-2aa6 ^napp-o6d6 ^napp-mbpr ^napp-433c
   ^napp-57qi ^napp-noiv ^napp-dnru ^nfix-j678 ^napp-deps and, after
   ^nnoschema-ttb5 removed the schema DSL: ^nnoschema-5mdj (derived config,
   environment function), ^nnoschema-zi2m (decode failure), ^nnoschema-ifg0
   (redaction by type), ^nnoschema-36cj (config check prints yojson_of_t),
   ^nnoschema-boxo (TOML-to-JSON stays here), ^nnoschema-p7fv (a two-Service
   program on a derived config type). ^napp-yplu's unknown-key refusal stands
   (^nnoschema-zi2m carries it into the derived decoder); ^napp-tuvw's
   schema-declared overrides are superseded. *)
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

(* ^nnoschema-5mdj: the consumer's config is a plain record with [@@deriving
   yojson]. The secret is typed [Redact.t], so it is redacted by being of that
   type; it is an option because the environment, not the file, supplies it. *)
type models = { api_key : Eta_observability.Redact.t option } [@@deriving yojson]
type settings = { models : models; port : int } [@@deriving yojson]

(* ^nnoschema-5mdj: what the Door takes is the type's derived decoder, its
   derived encoder (for [config check]) and the environment function. Applied
   after decoding, so a field the environment supplies is optional or carries
   [@default]; an override that does not parse is ignored. *)
let config : settings Config.t =
  {
    of_yojson = settings_of_yojson;
    yojson_of_t = yojson_of_settings;
    env =
      (fun ~getenv (settings : settings) ->
        let settings =
          match getenv "OPENROUTER_API_KEY" with
          | Some key ->
              {
                settings with
                models = { api_key = Some (Eta_observability.Redact.make key) };
              }
          | None -> settings
        in
        match getenv "PORT" with
        | Some raw -> (
            match int_of_string_opt raw with
            | Some port -> { settings with port }
            | None -> settings)
        | None -> settings);
  }

let good = "port = 42\n[models]\napi_key = \"file-secret\"\n"
let getenv = function "HOME" -> Some "/home/demo" | _ -> None
let pp_err fmt = function `Problem message -> Format.pp_print_string fmt message

let run ?(argv = [| "demo" |]) ?(text = good) ?(envvars = getenv) ?on_switch ?validate
    ?(read_path = fun _ -> ()) ?(program = fun _ _ _ -> Ok ()) () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
          method fs = base#fs
        end
      in
      let output = Buffer.create 80 and errors = Buffer.create 80 in
      let memory = Eta_observability.Logger.Memory.create () in
      let code =
        run_for_test ?on_switch ?validate ~env ~name:"demo" ~config ~pp_err
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

(* ^nnoschema-5mdj: the derived decoder and encoder are the config's single
   description; ^nnoschema-ifg0: a secret field encodes as "<redacted>". *)
let decode_json text =
  match config.of_yojson (Yojson.Safe.from_string text) with
  | Ok settings -> settings
  | Error message -> Alcotest.failf "derived decode of %s: %s" text message

let test_derived_config () =
  let settings = decode_json {|{"models":{"api_key":"file-secret"},"port":42}|} in
  check_int "^nnoschema-5mdj a typed field decodes" 42 settings.port;
  check_string "^nnoschema-ifg0 the secret arrives wrapped" "file-secret"
    (Eta_observability.Redact.expose (Option.get settings.models.api_key));
  let encoded = Yojson.Safe.to_string (config.yojson_of_t settings) in
  expect_part encoded "\"api_key\":\"<redacted>\"";
  Alcotest.(check bool)
    "^nnoschema-ifg0 the secret is absent from the encoded config" false
    (contains encoded "file-secret");
  let absent = Yojson.Safe.from_string {|{"models":{"api_key":null},"port":7}|} in
  let decoded = decode_json {|{"models":{"api_key":null},"port":7}|} in
  Alcotest.(check (option string))
    "an absent secret is None" None
    (Option.map Eta_observability.Redact.expose decoded.models.api_key);
  Alcotest.(check bool)
    "^nnoschema-5mdj yojson_of_t round-trips a config without secrets" true
    (Yojson.Safe.equal absent (config.yojson_of_t decoded))

let test_clean () =
  let started = ref false in
  let program env settings _ =
    started := true;
    check_int "^nnoschema-5mdj derived config reaches the program" 42 settings.port;
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

(* ^nnoschema-p7fv: the two-Service program takes the derived config type, so the
   shape consumers write is the shape tested. *)
module First :
  SERVICE
    with type t = int ref
     and type config = settings
     and type deps = string list ref
     and type error = [ `Problem of string ] = struct
  type t = int ref
  type config = settings
  type deps = string list ref
  type error = [ `Problem of string ]

  let create ~sw (settings : settings) events =
    events := !events @ [ "first:" ^ string_of_int settings.port ];
    Eio.Switch.on_release sw (fun () -> events := !events @ [ "release-first" ]);
    Ok (ref 1)

  let status t = Status.make ~details:[ ("counter", string_of_int !t) ] "first" Status.Ok
end

module Second :
  SERVICE
    with type t = int ref
     and type config = settings
     and type deps = int ref * string list ref
     and type error = [ `Problem of string ] = struct
  type t = int ref
  type config = settings
  type deps = int ref * string list ref
  type error = [ `Problem of string ]

  let create ~sw (settings : settings) (first, events) =
    events := !events @ [ "second:" ^ string_of_int settings.port ];
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
     and type config = settings
     and type deps = unit -> Status.t list
     and type error = [ `Problem of string ] = struct
  type t = unit -> Status.t list
  type config = settings
  type deps = unit -> Status.t list
  type error = [ `Problem of string ]

  let create ~sw:_ _settings query = Ok query

  let status query =
    let seen = List.map (fun status -> status.Status.name) (query ()) in
    Status.make ~details:[ ("seen", String.concat "," seen) ] "reporter" Status.Ok
end

let test_status_query_before_serve () =
  let events = ref [] in
  let id = Eta.Interrupt_id.create () in
  let live = ref [] and counter = ref "" and seen = ref "" and reporter = ref "" in
  let status_count = ref 0 in
  let program _ settings sw =
    let open Result in
    let* first = First.create ~sw settings events in
    let* second = Second.create ~sw settings (first, events) in
    let query =
      status_query [ (fun () -> First.status first); (fun () -> Second.status second) ]
    in
    let* reporter_service = Reporter.create ~sw settings query in
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
    "^napp-78pf reverse release ^napp-qg7n two services ^nnoschema-p7fv both got the \
     derived config"
    [ "first:42"; "second:42"; "release-second"; "release-first" ]
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

(* ^napp-78pf: the live consumer has daemon fibers that re-raise cancellation.
   Eio then propagates [Cancelled (Cancelled (Stop id))], not only the original
   switch failure. Start the service fiber before requesting shutdown. *)
let test_daemon_stop () =
  let stop_id = Eta.Interrupt_id.create () in
  let code, _, err, _ =
    run
      ~on_switch:(fun sw ->
        Eio.Fiber.fork_daemon ~sw (fun () ->
            Eio.Fiber.yield ();
            request_stop ~sw stop_id;
            `Stop_daemon))
      ~program:(fun _ _ sw ->
        Eio.Fiber.fork_daemon ~sw (fun () -> Eio.Fiber.await_cancel ());
        serve ~sw ())
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

(* ^nnoschema-zi2m: a decode failure prints the deriver's message — the dotted
   path of the offending value plus the value itself, bounded — and exits 2
   without starting. A key the type does not name is such a failure: ^napp-yplu's
   unknown-key rule stands, now with the deriver's path and key in the message,
   which is what Leash svc-ljl3 needs at boot. *)
let test_decode_failure () =
  let refused name text =
    let started = ref false in
    let code, _, err, _ =
      run ~text
        ~program:(fun _ _ _ ->
          started := true;
          Ok ())
        ()
    in
    check_int ("^nnoschema-zi2m " ^ name) 2 code;
    Alcotest.(check bool) "never starts" false !started;
    err
  in
  let err = refused "a missing field" "[models]\napi_key = \"a\"\n" in
  expect_part err "missing field port";
  let err = refused "a wrong type" "port = \"bad\"\n[models]\n" in
  expect_part err "settings.port";
  expect_part err "expected int";
  expect_part err "\"bad\"";
  (* The path restarts at the nested type, as the deriver documents: the message names
     the field, the nested type's own path, and the value. *)
  let err =
    refused "a wrong type in a nested record" "port = 1\n[models]\napi_key = 7\n"
  in
  expect_part err "settings.models";
  expect_part err "models.api_key";
  expect_part err "expected string";
  expect_part err "got 7";
  (* ^napp-yplu ^nnoschema-zi2m: an unknown key fails at boot, naming the path and
     the key, and the program is never entered. *)
  let err = refused "an unknown key" "port = 1\n[models]\napi_key = \"a\"\nextra = 1\n" in
  expect_part err "settings";
  expect_part err "unknown field extra";
  let err =
    refused "an unknown key in a nested table" "port = 1\n[models]\nextra = 1\n"
  in
  expect_part err "settings.models";
  expect_part err "unknown field extra"

(* ^nnoschema-5mdj ^nnoschema-36cj ^nnoschema-ifg0: the environment function runs
   on the decoded value, and config check prints the effective config after the
   overrides with secrets redacted by type. *)
let test_env_override_and_check () =
  let envvars = function
    | "OPENROUTER_API_KEY" -> Some "override-secret"
    | "PORT" -> Some "73"
    | "HOME" -> Some "/home/demo"
    | _ -> None
  in
  let code, _, err, _ =
    run ~envvars ~text:"port = 3\n[models]\n"
      ~program:(fun _ cfg _ ->
        check_int "^nnoschema-5mdj typed environment override" 73 cfg.port;
        check_string "the environment fills the optional secret" "override-secret"
          (Eta_observability.Redact.expose (Option.get cfg.models.api_key));
        Ok ())
      ()
  in
  check_int "the Door accepts the effective config" 0 code;
  check_string "no diagnostics" "" err;
  let code, out, err, _ =
    run
      ~argv:[| "demo"; "config"; "check" |]
      ~envvars
      ~program:(fun _ _ _ -> failwith "must not start")
      ()
  in
  check_int "^nnoschema-36cj check exits zero" 0 code;
  check_string "no error" "" err;
  expect_part out "\"port\":73";
  expect_part out "\"api_key\":\"<redacted>\"";
  Alcotest.(check bool)
    "^nnoschema-ifg0 the environment secret never reaches the check output" false
    (contains out "override-secret");
  Alcotest.(check bool)
    "^nnoschema-ifg0 nor does the one in the file" false (contains out "file-secret");
  let code, out, err, _ =
    run ~text:"port = \"bad\"\n[models]\n" ~argv:[| "demo"; "config"; "check" |] ()
  in
  check_int "^nnoschema-36cj check of an invalid config exits 2" 2 code;
  check_string "and prints nothing" "" out;
  expect_part err "settings.port"

(* ^napp-57qi ^napp-dnru: a failing validator stops the Door before the program's switch,
   and its errors render like decode issues. *)
let test_validate_blocks () =
  let started = ref false in
  let validate _ _ =
    Error
      [
        { Config.pointer = "/port"; message = "port 42 is not available" };
        { Config.pointer = ""; message = "chrome is not executable" };
      ]
  in
  let code, out, err, _ =
    run ~validate
      ~program:(fun _ _ _ ->
        started := true;
        Ok ())
      ()
  in
  check_int "^napp-57qi failing validator exits 2" 2 code;
  check_string "^napp-57qi nothing printed for the program" "" out;
  expect_part err "/port";
  expect_part err "port 42 is not available";
  expect_part err "chrome is not executable";
  Alcotest.(check bool) "^napp-57qi program never entered" false !started

(* ^napp-57qi: the validator runs after decoding and the environment overrides, with the
   Door's Env. *)
let test_validate_env_and_config () =
  let envvars = function
    | "OPENROUTER_API_KEY" -> Some "override-secret"
    | "PORT" -> Some "73"
    | "HOME" -> Some "/home/demo"
    | _ -> None
  in
  let seen_port = ref 0 in
  let validate env cfg =
    seen_port := cfg.port;
    Eta_observability.Logger.info env.Env.logger "validated";
    Ok ()
  in
  let code, _, err, logs = run ~validate ~envvars ~text:"port = 3\n[models]\n" () in
  check_int "^napp-57qi validator accepts the effective config" 0 code;
  check_string "no diagnostics" "" err;
  check_int "^napp-57qi env override applied before validation" 73 !seen_port;
  Alcotest.(check int)
    "^napp-57qi validator got the Door's Env" 1
    (List.length (Eta_observability.Logger.Memory.find logs))

(* ^napp-57qi: an environment-dependent check reads the capability the Door passed: the
   validator accepts the file while it exists and fails once it is gone, like a check for
   the Chrome binary the problem statement names. *)
let test_validate_uses_door_fs () =
  let path = Filename.temp_file "eta-app-validate-" ".bin" in
  let validate env cfg =
    match cfg.models.api_key with
    | Some key
      when Eio.Path.is_file
             Eio.Path.(env.Env.base#fs / Eta_observability.Redact.expose key) ->
        Ok ()
    | _ -> Error [ { Config.pointer = "/models/api_key"; message = "no such file" } ]
  in
  let text = Printf.sprintf "port = 42\n[models]\napi_key = %S\n" path in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      let code, _, err, _ = run ~validate ~text () in
      check_int "^napp-57qi validator sees the Door's fs" 0 code;
      check_string "no diagnostics" "" err;
      Sys.remove path;
      let code, _, err, _ = run ~validate ~text () in
      check_int "^napp-57qi missing environment file exits 2" 2 code;
      expect_part err "/models/api_key";
      expect_part err "no such file")

(* ^napp-57qi ^napp-noiv: a raising validator is a defect on both paths. *)
let test_validate_defect () =
  let validate _ _ = failwith "validator exploded" in
  let code, _, err, _ = run ~validate () in
  check_int "^napp-57qi raising validator exits 2" 2 code;
  expect_part err "validator exploded";
  let code, _, err, _ = run ~validate ~argv:[| "demo"; "config"; "check" |] () in
  check_int "^napp-noiv check agrees on a raising validator" 2 code;
  expect_part err "validator exploded"

(* ^napp-noiv: config check runs the validator, reports its errors with their pointers and
   prints the config only when it accepts. *)
let test_check_validates () =
  let calls = ref 0 in
  let validate _ cfg =
    incr calls;
    if cfg.port = 42 then Ok ()
    else Error [ { Config.pointer = "/port"; message = "port out of range" } ]
  in
  let code, out, err, _ =
    run ~validate
      ~argv:[| "demo"; "config"; "check" |]
      ~program:(fun _ _ _ -> failwith "must not start")
      ()
  in
  check_int "^napp-noiv check passes a passing validator" 0 code;
  check_int "^napp-noiv check ran the validator" 1 !calls;
  check_string "no error" "" err;
  expect_part out "<redacted>";
  let code, out, err, _ =
    run ~validate
      ~argv:[| "demo"; "config"; "check" |]
      ~text:"port = 3\n[models]\napi_key = \"a\"\n"
      ~program:(fun _ _ _ -> failwith "must not start")
      ()
  in
  check_int "^napp-noiv check fails with the validator" 2 code;
  check_string "^napp-noiv no config printed" "" out;
  expect_part err "/port";
  expect_part err "port out of range"

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
        run_for_test ~commands:[ hook ] ~env ~name:"demo" ~config ~pp_err
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
  check_int "^nnoschema-boxo malformed TOML" 2 code;
  expect_part err "TOML line";
  (* ^nnoschema-boxo: the TOML-to-JSON step stays in the Door and still refuses
     what JSON cannot carry, naming the pointer of the value. *)
  let code, _, err, _ = run ~text:"port = 1\nat = 1979-05-27\n[models]\n" () in
  check_int "a TOML date exits 2" 2 code;
  expect_part err "TOML dates have no JSON representation";
  expect_part err "/at";
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let err = Buffer.create 32 in
      let code =
        run_for_test ~env ~name:"demo" ~config ~pp_err
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

(* ^napp-57qi: Eta_app.run itself, not only run_for_test, runs the validator before the
   program's switch. The fixture is the only executable that goes through Eta_app.run. *)
let test_run_validates () =
  let config_path = Filename.temp_file "eta-app-validate-run-" ".toml" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists config_path then Sys.remove config_path)
    (fun () ->
      let output = open_out config_path in
      output_string output "port = 7\n";
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
                | Error _ -> Alcotest.fail "invalid validator fixture spawn"
              in
              let status =
                Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                    Eta_process.Child.await child)
              in
              Alcotest.(check bool)
                "^napp-57qi run exits 2 without starting" true
                (match status with Eta_process.Child.Exited 2 -> true | _ -> false);
              let errors =
                Eio.Flow.read_all (Option.get (Eta_process.Child.stderr child))
              in
              expect_part errors "/port";
              expect_part errors "port rejected by validator";
              let printed =
                Eio.Flow.read_all (Option.get (Eta_process.Child.stdout child))
              in
              check_string "^napp-57qi the program never printed" "" printed)))

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
          Alcotest.test_case "^nnoschema-5mdj ^nnoschema-ifg0 derived config" `Quick
            test_derived_config;
          Alcotest.test_case "^napp-f7d6 typed defect composite" `Quick test_failures;
          Alcotest.test_case "^napp-f7d6 foreign interruption" `Quick
            test_foreign_interruption;
          Alcotest.test_case
            "^napp-78pf ^napp-qg7n ^napp-pn0a ^napp-kq3b ^napp-433c ^nfix-j678 \
             ^nnoschema-p7fv"
            `Quick test_status_query_before_serve;
          Alcotest.test_case "^napp-78pf child fiber stop" `Quick test_daemon_stop;
          Alcotest.test_case "^napp-2aa6 path precedence" `Quick test_config;
          Alcotest.test_case "^nnoschema-zi2m decode failures" `Quick test_decode_failure;
          Alcotest.test_case
            "^nnoschema-5mdj ^nnoschema-36cj ^nnoschema-ifg0 env and check" `Quick
            test_env_override_and_check;
          Alcotest.test_case "^napp-57qi ^napp-dnru validator blocks" `Quick
            test_validate_blocks;
          Alcotest.test_case "^napp-57qi validator env and effective config" `Quick
            test_validate_env_and_config;
          Alcotest.test_case "^napp-57qi validator uses the Door's fs" `Quick
            test_validate_uses_door_fs;
          Alcotest.test_case "^napp-57qi ^napp-noiv raising validator" `Quick
            test_validate_defect;
          Alcotest.test_case "^napp-noiv check runs the validator" `Quick
            test_check_validates;
          Alcotest.test_case "^napp-3j07 command hook ^napp-deps deps" `Quick
            test_cli_hook;
          Alcotest.test_case "^napp-2aa6 ^nnoschema-boxo CLI and IO errors" `Quick
            test_cli_and_io_errors;
          Alcotest.test_case "^napp-57qi run runs the validator" `Quick test_run_validates;
          Alcotest.test_case "nlimit-s3f4 real SIGTERM" `Quick
            (test_real_signal Sys.sigterm);
          Alcotest.test_case "nlimit-s3f4 real SIGINT" `Quick
            (test_real_signal Sys.sigint);
        ] );
    ]
