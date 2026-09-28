(* Story IDs covered: ^napp-ytqk ^napp-x11e ^napp-ersz ^napp-3j07 ^napp-78pf ^napp-f7d6 ^napp-qg7n
   ^napp-pn0a ^napp-kq3b ^napp-2aa6 ^napp-o6d6 ^napp-mbpr ^napp-433c
   ^napp-57qi ^napp-noiv ^napp-dnru ^nfix-j678 ^napp-deps ^napp-idii and, after
   ^nnoschema-ttb5 removed the schema DSL, and ^notel-1stb (the Door's real SIGTERM
   stop exports pending OTLP telemetry without a shutdown call): ^nnoschema-5mdj
   (derived config, environment function), ^nnoschema-zi2m (decode failure), ^nnoschema-ifg0
   (redaction by type), ^nnoschema-36cj (config check prints yojson_of_t),
   ^nnoschema-boxo (TOML-to-JSON stays here), ^nnoschema-p7fv (a two-Service
   program on a derived config type), ^napp-9x0s (an absent file at the default path is
   the empty document) and ^napp-d5e4 (the Door's start command is named by the service
   author, so a program can use `run` for a verb of its own). ^napp-yplu's unknown-key
   refusal stands
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

let index_of hay needle =
  let rec go i =
    if i + String.length needle > String.length hay then -1
    else if String.sub hay i (String.length needle) = needle then i
    else go (i + 1)
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
   [@json.default]; an override that does not parse is ignored. *)
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

(* ^napp-9x0s: [read] is the read outcome the Door sees; the default is a file that is
   there and holds [text], which is what every other case wants. *)
let run ?(argv = [| "demo" |]) ?(text = good) ?(envvars = getenv) ?on_switch ?validate
    ?telemetry ?(read_path = fun _ -> ()) ?read ?(program = fun _ _ _ -> Ok ()) () =
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
        run_for_test ?on_switch ?validate ?telemetry ~env ~name:"demo" ~config ~pp_err
          ~journal:(Eta_observability.Logger.Memory.reporter memory)
          ~getenv:envvars
          ~read:(fun path ->
            read_path path;
            match read with Some read -> read path | None -> Ok text)
          ~stderr:(fun text -> Buffer.add_string errors text)
          ~stdout:(fun text -> Buffer.add_string output text)
          ~argv program
      in
      (code, Buffer.contents output, Buffer.contents errors, memory))

(* ^napp-9x0s: the story's shape is a config type whose fields carry defaults, so the
   empty document the Door decodes for an absent default file is a valid configuration. *)
type defaults = { port : int [@json.default 4242] } [@@deriving yojson]

let defaults_config : defaults Config.t =
  {
    of_yojson = defaults_of_yojson;
    yojson_of_t = yojson_of_defaults;
    env = (fun ~getenv:_ settings -> settings);
  }

(* ^napp-9x0s: the Door over whichever config type a case needs, in a scheduler the case
   owns. [config] is a parameter, not a default, so this stays polymorphic over the config
   type, and one scheduler serves several invocations of the Door — only the argv and the
   read outcome change between them. *)
let door ~env ~config ?(argv = [| "demo" |]) ?(read_path = fun _ -> ())
    ?(read = fun _ -> Ok "") ?(program = fun _ _ _ -> Ok ()) () =
  let output = Buffer.create 80 and errors = Buffer.create 80 in
  let code =
    run_for_test ~env ~name:"demo" ~config ~pp_err
      ~journal:
        (Eta_observability.Logger.Memory.reporter
           (Eta_observability.Logger.Memory.create ()))
      ~getenv
      ~read:(fun path ->
        read_path path;
        read path)
      ~stderr:(fun text -> Buffer.add_string errors text)
      ~stdout:(fun text -> Buffer.add_string output text)
      ~argv program
  in
  (code, Buffer.contents output, Buffer.contents errors)

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
  let absent = Yojson.Safe.from_string {|{"models":{},"port":7}|} in
  let decoded = decode_json {|{"models":{"api_key":null},"port":7}|} in
  Alcotest.(check (option string))
    "an absent secret is None" None
    (Option.map Eta_observability.Redact.expose decoded.models.api_key);
  Alcotest.(check bool)
    "^nnoschema-5mdj ^nderive-mmnx missing or null secret encodes omitted" true
    (Yojson.Safe.equal absent (config.yojson_of_t decoded))

let test_clean () =
  let started = ref false in
  let program env (settings : settings) _ =
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

(* ^napp-9x0s: no --config and no file at the default path is the empty document, so the
   program starts on the type's defaults; the same absence at a path the operator named is
   an error naming it; config check follows the same rule; and a file that is there and
   cannot be read is an error at the default path too. *)
let test_absent_default_config () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
          method fs = base#fs
        end
      in
      let started = ref false and seen = ref "" in
      let code, _, err =
        door ~env ~config:defaults_config
          ~read_path:(fun path -> seen := path)
          ~read:(fun _ -> Error `Missing)
          ~program:(fun _ (cfg : defaults) _ ->
            started := true;
            check_int "^napp-9x0s the empty document decoded to the defaults" 4242
              cfg.port;
            Ok ())
          ()
      in
      check_int "^napp-9x0s a missing default file starts the program" 0 code;
      check_string "^napp-9x0s and reports no error" "" err;
      check_string "^napp-9x0s the Door read its own default path"
        "/home/demo/.config/demo/config.toml" !seen;
      Alcotest.(check bool) "^napp-9x0s the program ran" true !started;
      let code, out, err =
        door ~env ~config:defaults_config
          ~argv:[| "demo"; "config"; "check" |]
          ~read:(fun _ -> Error `Missing)
          ~program:(fun _ _ _ -> failwith "check must not start the program")
          ()
      in
      check_int "^napp-9x0s config check of an absent default file exits 0" 0 code;
      check_string "no error" "" err;
      expect_part out "\"port\":4242";
      let code, _, err =
        door ~env ~config:defaults_config
          ~argv:[| "demo"; "--config"; "absent.toml" |]
          ~read:(fun _ -> Error `Missing)
          ~program:(fun _ _ _ -> failwith "must not start the program")
          ()
      in
      check_int "^napp-9x0s an absent --config path exits 2" 2 code;
      expect_part err "absent.toml";
      expect_part err "no such file";
      let code, out, err =
        door ~env ~config:defaults_config
          ~argv:[| "demo"; "config"; "check"; "--config"; "absent.toml" |]
          ~read:(fun _ -> Error `Missing)
          ~program:(fun _ _ _ -> failwith "must not start the program")
          ()
      in
      check_int "^napp-9x0s config check agrees about --config" 2 code;
      check_string "^napp-9x0s and prints no config" "" out;
      expect_part err "absent.toml";
      let code, _, err =
        door ~env ~config:defaults_config
          ~read:(fun _ -> Error (`Unreadable "permission denied"))
          ~program:(fun _ _ _ -> failwith "must not start the program")
          ()
      in
      check_int "^napp-9x0s a default file that cannot be read exits 2" 2 code;
      expect_part err "/home/demo/.config/demo/config.toml";
      expect_part err "permission denied";
      (* The absence is decoded, not tolerated blindly: a config type without defaults
         still refuses the empty document. *)
      let code, _, err =
        door ~env ~config
          ~read:(fun _ -> Error `Missing)
          ~program:(fun _ _ _ -> failwith "must not start the program")
          ()
      in
      check_int "^napp-9x0s a type without defaults still refuses the empty document" 2
        code;
      expect_part err "missing field models")

(* ^napp-9x0s: the Door's own read — not only run_for_test's — classifies Eio's Not_found
   as absence, so the real executable starts on its defaults when the default path holds no
   file, config check prints those defaults, and the path --config names must exist. The
   fixture runs with XDG_CONFIG_HOME pointing at a directory that is not there. *)
let test_default_path_absent () =
  let absent =
    Filename.concat
      (Filename.get_temp_dir_name ())
      (Printf.sprintf "eta-app-absent-%d" (Unix.getpid ()))
  in
  let missing = Filename.concat absent "config.toml" in
  let env =
    Array.of_list
      (("XDG_CONFIG_HOME=" ^ absent)
      :: List.filter
           (fun entry -> not (String.starts_with ~prefix:"XDG_CONFIG_HOME=" entry))
           (Array.to_list (Unix.environment ())))
  in
  Eio_main.run (fun base ->
      Eio.Switch.run (fun sw ->
          let fixture =
            Filename.concat (Filename.dirname Sys.executable_name) "signal_fixture.exe"
          in
          let spawn argv =
            match
              Eta_process.Child.spawn ~sw ~clock:base#clock ~mgr:base#process_mgr ~argv
                ~env ~grace:(Eta.Duration.ms 50) ~stdout:Eta_process.Child.Pipe
                ~stderr:Eta_process.Child.Pipe ~fds:[] ()
            with
            | Ok child -> child
            | Error _ -> Alcotest.fail "invalid absent-config fixture spawn"
          in
          let await child =
            Eio.Time.with_timeout_exn base#clock 5. (fun () ->
                Eta_process.Child.await child)
          in
          let code_of status =
            match status with Eta_process.Child.Exited code -> code | _ -> -1
          in
          let printed child =
            Eio.Flow.read_all (Option.get (Eta_process.Child.stdout child))
          in
          let errors child =
            Eio.Flow.read_all (Option.get (Eta_process.Child.stderr child))
          in
          (* No file at the default path: the program starts, as a fresh install must. *)
          let child = spawn [ fixture ] in
          let ready =
            Eio.Time.with_timeout_exn base#clock 5. (fun () ->
                Eio.Buf_read.line
                  (Eio.Buf_read.of_flow ~max_size:1024
                     (Option.get (Eta_process.Child.stdout child))))
          in
          check_string "Door ready" "ready" ready;
          Eta_process.Child.signal child Sys.sigterm;
          check_int "^napp-9x0s the real Door starts with no config file" 0
            (code_of (await child));
          (* ^napp-d5e4: the fixture asks the Door to call its start command `serve`, so
             this spawn proves Eta_app.run forwards the name; the spawn above started the
             same program through the group's default term. *)
          let child = spawn [ fixture; "serve" ] in
          let ready =
            Eio.Time.with_timeout_exn base#clock 5. (fun () ->
                Eio.Buf_read.line
                  (Eio.Buf_read.of_flow ~max_size:1024
                     (Option.get (Eta_process.Child.stdout child))))
          in
          check_string "Door ready" "ready" ready;
          Eta_process.Child.signal child Sys.sigterm;
          check_int "^napp-d5e4 the real Door starts under the name its author gave" 0
            (code_of (await child));
          (* config check sees the same defaults. *)
          let child = spawn [ fixture; "config"; "check" ] in
          let status = await child in
          let out = printed child and err = errors child in
          check_int "^napp-9x0s the real config check exits zero" 0 (code_of status);
          check_string "no diagnostics" "" err;
          expect_part out "\"port\":4242";
          (* An explicit --config that is not there is still an error naming it. *)
          let child = spawn [ fixture; "config"; "check"; "--config"; missing ] in
          let status = await child in
          let out = printed child and err = errors child in
          check_int "^napp-9x0s a missing --config exits 2" 2 (code_of status);
          check_string "^napp-9x0s and prints no config" "" out;
          expect_part err missing;
          expect_part err "no such file"))

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
      ~program:(fun _ (cfg : settings) _ ->
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
  let validate env (cfg : settings) =
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
  let validate _ (cfg : settings) =
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

(* ^napp-idii: the telemetry hook runs after decoding and validation, its reporters
   receive every record the program's logger writes alongside the journal, its span ID
   generator is the program logger's, and its root-switch resource is released before
   the Door returns. *)
let test_telemetry_hook () =
  let seen = ref [] and released = ref false in
  let hook ~sw env (cfg : settings) =
    check_int "^napp-idii the hook gets the validated config" 42 cfg.port;
    Alcotest.(check bool)
      "^napp-idii and the Door's own logger" true
      (Eta_observability.Logger.enabled env.Env.logger Eta_observability.Logger.Info);
    Eio.Switch.on_release sw (fun () -> released := true);
    {
      reporters =
        [
          Eta_observability.Logger.Reporter.records (fun record ->
              seen := record :: !seen);
        ];
      span_ids = Some (fun () -> String.make 32 'a');
    }
  in
  let code, _, err, journal =
    run ~telemetry:hook
      ~program:(fun env _ _ ->
        ignore
          (Eta_observability.Logger.span env.Env.logger "unit" (fun () -> Ok ())
            : (unit, string) result);
        Ok ())
      ()
  in
  check_int "^napp-idii the Door still exits clean" 0 code;
  check_string "no diagnostics" "" err;
  let seen = List.rev !seen in
  check_int "^napp-idii the telemetry reporter receives every record" 2 (List.length seen);
  check_int "the journal receives them too" 2
    (List.length (Eta_observability.Logger.Memory.records journal));
  Alcotest.(check bool)
    "^napp-idii the hook's span IDs are the program logger's" true
    (List.for_all
       (fun record -> List.mem_assoc "trace_id" record.Eta_observability.Logger.context)
       seen);
  Alcotest.(check bool)
    "^napp-idii the root switch released the hook's resource before the Door returned"
    true !released

(* ^napp-idii: a hook that raises is a defect on the run path, rendered and exiting 2
   without entering the program. *)
let test_telemetry_defect () =
  let started = ref false in
  let code, _, err, _ =
    run
      ~telemetry:(fun ~sw:_ _ _ -> failwith "exporter exploded")
      ~program:(fun _ _ _ ->
        started := true;
        Ok ())
      ()
  in
  check_int "^napp-idii a raising hook exits 2" 2 code;
  expect_part err "exporter exploded";
  Alcotest.(check bool) "^napp-idii the program never ran" false !started

(* ^napp-idii: config check configures nothing, so the hook is not called there. *)
let test_telemetry_check_path () =
  let calls = ref 0 in
  let code, out, err, _ =
    run
      ~argv:[| "demo"; "config"; "check" |]
      ~telemetry:(fun ~sw:_ _ _ ->
        incr calls;
        { reporters = []; span_ids = None })
      ~program:(fun _ _ _ -> failwith "must not start")
      ()
  in
  check_int "^napp-idii check exits zero" 0 code;
  check_int "^napp-idii config check does not configure telemetry" 0 !calls;
  check_string "no error" "" err;
  expect_part out "\"port\":42"

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

(* ^napp-wf22: the Door's own config group takes a consumer subcommand beside check, so
   `<name> config init` exists, runs, and is listed in the group's help. *)
let test_config_commands () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let calls = ref 0 in
      let init =
        Cmdliner.Cmd.v (Cmdliner.Cmd.info "init")
          Cmdliner.Term.(
            const (fun () ->
                incr calls;
                5))
      in
      let door ~argv ~stdout =
        run_for_test ~config_commands:[ init ] ~env ~name:"demo" ~config ~pp_err
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~getenv
          ~read:(fun _ -> failwith "a config subcommand must not load the config")
          ~stderr:ignore ~stdout ~argv
          (fun _ _ _ -> failwith "a config subcommand must not start the program")
      in
      let code = door ~argv:[| "demo"; "config"; "init" |] ~stdout:ignore in
      check_int "^napp-wf22 the consumer subcommand runs" 5 code;
      check_int "and is invoked once" 1 !calls;
      let output = Buffer.create 256 in
      let code =
        door ~argv:[| "demo"; "config"; "--help" |] ~stdout:(fun text ->
            Buffer.add_string output text)
      in
      check_int "^napp-wf22 config help exits zero" 0 code;
      expect_part (Buffer.contents output) "init";
      expect_part (Buffer.contents output) "check";
      check_int "help ran nothing" 1 !calls)

(* ^napp-d5e4: the Door's start command carries the name the service author gives it, so a
   program can use `run` for a verb of its own. The group's default term is that same
   term, so a bare invocation starts the program under either name, and a service that
   never asks still gets `run`. *)
let test_service_command () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let started = ref 0 in
      let door ?service_command argv =
        run_for_test ?service_command ~env ~name:"demo" ~config ~pp_err
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~getenv
          ~read:(fun _ -> Ok good)
          ~stderr:ignore ~stdout:ignore ~argv
          (fun _ _ _ ->
            incr started;
            Ok ())
      in
      check_int "^napp-d5e4 the default command is still run" 0 (door [| "demo"; "run" |]);
      check_int "and it starts the program" 1 !started;
      check_int "a bare invocation starts the program" 0 (door [| "demo" |]);
      check_int "through the default term" 2 !started;
      check_int "^napp-d5e4 a custom name starts the program" 0
        (door ~service_command:"serve" [| "demo"; "serve" |]);
      check_int "and it started the program" 3 !started;
      check_int "^napp-d5e4 a bare invocation under a custom name starts the program" 0
        (door ~service_command:"serve" [| "demo" |]);
      check_int "through the default term again" 4 !started;
      (* The name a renamed Door no longer uses is no command at all: Cmdliner refuses it
         and the program is never entered. *)
      check_int "^napp-d5e4 the name it no longer uses is not a command" 2
        (door ~service_command:"serve" [| "demo"; "run" |]);
      check_int "and the program stayed down" 4 !started)

(* ^napp-d5e4 (Leash L31 run-9ypy): the shape the story exists for — a consumer command
   named `run` beside a Door whose start command is `serve`: `run` is the consumer's
   verb, `serve` starts the program, and neither shadows the other. *)
let test_service_command_coexists () =
  Eta_test.run (fun base _ ->
      let env =
        object
          method clock = base#clock
          method mono_clock = base#mono_clock
        end
      in
      let started = ref 0 and verbs = ref 0 in
      let run_verb =
        Cmdliner.Cmd.v (Cmdliner.Cmd.info "run")
          Cmdliner.Term.(
            const (fun () ->
                incr verbs;
                3))
      in
      let door argv =
        run_for_test ~service_command:"serve" ~commands:[ run_verb ] ~env ~name:"demo"
          ~config ~pp_err
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~getenv
          ~read:(fun _ -> Ok good)
          ~stderr:ignore ~stdout:ignore ~argv
          (fun _ _ _ ->
            incr started;
            Ok ())
      in
      check_int "^napp-d5e4 the consumer's run command is dispatched" 3
        (door [| "demo"; "run" |]);
      check_int "and it is the consumer's own" 1 !verbs;
      check_int "^napp-d5e4 while the program did not start" 0 !started;
      check_int "the Door's renamed start command starts the program" 0
        (door [| "demo"; "serve" |]);
      check_int "the program started" 1 !started;
      check_int "and the consumer's verb still ran once" 1 !verbs)

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
          ~read:(fun _ -> Error (`Unreadable "no such file"))
          ~stderr:(fun text -> Buffer.add_string err text)
          ~stdout:ignore ~argv:[| "demo" |]
          (fun _ _ _ -> failwith "must not start")
      in
      check_int "^napp-2aa6 ^napp-9x0s unreadable config" 2 code;
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

(* ^napp-idii: the telemetry the program's config switches on receives the program's
   record on the real SIGTERM path, and its root-switch resource flushes before the
   process exits. *)
let test_real_signal_telemetry () =
  let config_path = Filename.temp_file "eta-app-telemetry-" ".toml" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists config_path then Sys.remove config_path)
    (fun () ->
      let output = open_out config_path in
      output_string output "port = 42\ntelemetry = true\n";
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
                | Error _ -> Alcotest.fail "invalid telemetry fixture spawn"
              in
              let input =
                Eio.Buf_read.of_flow ~max_size:65536
                  (Option.get (Eta_process.Child.stdout child))
              in
              let ready =
                Eio.Time.with_timeout_exn env#clock 5. (fun () -> Eio.Buf_read.line input)
              in
              check_string "Door ready" "ready" ready;
              Eta_process.Child.signal child Sys.sigterm;
              let status =
                Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                    Eta_process.Child.await child)
              in
              Alcotest.(check bool)
                "signal maps to exit code zero" true
                (match status with Eta_process.Child.Exited 0 -> true | _ -> false);
              let printed = Eio.Buf_read.take_all input in
              expect_part printed "\"msg\":\"signal stopped\"";
              expect_part printed "telemetry flushed";
              Alcotest.(check bool)
                "^napp-idii the reporter saw the record before the root switch flushed"
                true
                (index_of printed "\"msg\":\"signal stopped\""
                < index_of printed "telemetry flushed"))))

(* ^notel-1stb: the smallest OTLP collector: it records every POSTed body and answers
   200, so a test can see what an exporter sent during a Door stop. *)
let with_otlp_collector env sw f =
  let listener =
    Eio.Net.listen ~sw ~backlog:8 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
  in
  let port =
    match Eio.Net.listening_addr listener with
    | `Tcp (_, port) -> port
    | _ -> assert false
  in
  let received = ref [] in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      while true do
        let flow, _ = Eio.Net.accept ~sw listener in
        let input = Eio.Buf_read.of_flow ~max_size:262144 flow in
        ignore (Eio.Buf_read.line input : string);
        let rec headers length =
          let line = Eio.Buf_read.line input in
          if line = "" then length
          else
            let prefix = "content-length:" in
            let lower = String.lowercase_ascii line in
            let length =
              if String.starts_with ~prefix lower then
                int_of_string
                  (String.trim
                     (String.sub line (String.length prefix)
                        (String.length line - String.length prefix)))
              else length
            in
            headers length
        in
        received := Eio.Buf_read.take (headers 0) input :: !received;
        Eio.Flow.copy_string "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n" flow
      done;
      `Stop_daemon);
  f port received

let otlp_messages bodies =
  List.concat_map
    (fun body ->
      let document = Yojson.Safe.from_string body in
      let open Yojson.Safe.Util in
      document |> member "resourceLogs" |> to_list
      |> List.concat_map (fun resource ->
          resource |> member "scopeLogs" |> to_list
          |> List.concat_map (fun scope ->
              scope |> member "logRecords" |> to_list
              |> List.map (fun record ->
                  record |> member "body" |> member "stringValue" |> to_string))))
    bodies

(* ^notel-1stb: run the fixture to a real SIGTERM stop with a configured OTLP exporter
   and report its exit status, its stdout, and the messages the collector received. *)
let signal_stop_otlp env sw ~shutdown =
  let config_path = Filename.temp_file "eta-app-otlp-" ".toml" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists config_path then Sys.remove config_path)
    (fun () ->
      with_otlp_collector env sw (fun port received ->
          let output = open_out config_path in
          output_string output
            (Printf.sprintf
               "port = 42\n\
                telemetry = true\n\
                otlp_shutdown = %b\n\
                otlp_endpoint = \"http://127.0.0.1:%d/otlp\"\n"
               shutdown port);
          close_out output;
          let fixture =
            Filename.concat (Filename.dirname Sys.executable_name) "signal_fixture.exe"
          in
          let child =
            match
              Eta_process.Child.spawn ~sw ~clock:env#clock ~mgr:env#process_mgr
                ~argv:[ fixture; "--config"; config_path ]
                ~grace:(Eta.Duration.ms 50) ~stdout:Eta_process.Child.Pipe
                ~stderr:Eta_process.Child.Pipe ~fds:[] ()
            with
            | Ok child -> child
            | Error _ -> Alcotest.fail "invalid OTLP fixture spawn"
          in
          let input =
            Eio.Buf_read.of_flow ~max_size:65536
              (Option.get (Eta_process.Child.stdout child))
          in
          let ready =
            Eio.Time.with_timeout_exn env#clock 5. (fun () -> Eio.Buf_read.line input)
          in
          check_string "Door ready" "ready" ready;
          Eta_process.Child.signal child Sys.sigterm;
          let status =
            Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                Eta_process.Child.await child)
          in
          ( (match status with Eta_process.Child.Exited 0 -> true | _ -> false),
            Eio.Buf_read.take_all input,
            otlp_messages (List.rev !received) )))

(* ^notel-1stb: the exporter the telemetry hook builds exports on the root switch's
   release, so the record the program logs while SIGTERM stops it reaches the collector
   even though nothing calls Eta_otel.shutdown. *)
let test_real_signal_otlp () =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let clean, printed, messages = signal_stop_otlp env sw ~shutdown:false in
          Alcotest.(check bool) "signal maps to exit code zero" true clean;
          expect_part printed "telemetry flushed";
          Alcotest.(check (list string))
            "^notel-1stb the exporter itself exported the last record"
            [ "signal stopped" ] messages))

(* ^notel-1stb: the pre-fix consumer pattern — [Eta_otel.shutdown] registered with
   [Eio.Switch.on_release] — used to wait for the daemon the switch had already
   cancelled and hang the stop; the record logged just before it still arrives. *)
let test_real_signal_otlp_shutdown () =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let clean, _, messages = signal_stop_otlp env sw ~shutdown:true in
          Alcotest.(check bool)
            "^notel-1stb shutdown in a release hook does not hang the stop" true clean;
          Alcotest.(check (list string))
            "^notel-1stb and the last record still reaches the collector"
            [ "signal stopped" ] messages))

(* ^napp-ytqk: default and named invocation parse exactly one typed term. *)
(* ^napp-x11e: an extra long-lived verb uses production signal handling and
   completes its owned switch's finalizers before its process exits. *)
let test_door2_real_signal_extra () =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let fixture =
            Filename.concat (Filename.dirname Sys.executable_name) "signal_fixture.exe"
          in
          let child =
            match
              Eta_process.Child.spawn ~sw ~clock:env#clock ~mgr:env#process_mgr
                ~argv:[ fixture; "long" ] ~grace:(Eta.Duration.ms 50)
                ~stdout:Eta_process.Child.Pipe ~stderr:Eta_process.Child.Pipe ~fds:[] ()
            with
            | Ok child -> child
            | Error _ -> Alcotest.fail "invalid extra command fixture spawn"
          in
          let output =
            Eio.Buf_read.of_flow ~max_size:1024
              (Option.get (Eta_process.Child.stdout child))
          in
          let ready =
            Eio.Time.with_timeout_exn env#clock 5. (fun () -> Eio.Buf_read.line output)
          in
          check_string "^napp-x11e extra command ready" "ready" ready;
          Eta_process.Child.signal child Sys.sigterm;
          let status =
            Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                Eta_process.Child.await child)
          in
          Alcotest.(check bool)
            "SIGTERM clean exit" true
            (match status with Eta_process.Child.Exited 0 -> true | _ -> false);
          check_string "^napp-x11e release before exit" "command released"
            (Eio.Buf_read.line output);
          ignore (Eta_process.Child.stop child)))

(* ^napp-ersz: the production reader policy is actually wired to both startup
   and config check, not merely available as an isolated helper. *)
let test_door2_production_reader () =
  let file = Filename.temp_file "eta-door2-reader-" ".toml" in
  Fun.protect
    ~finally:(fun () -> Sys.remove file)
    (fun () ->
      let out = open_out file in
      output_string out (String.make 2048 'x');
      close_out out;
      Eio_main.run (fun env ->
          Eio.Switch.run (fun sw ->
              let fixture =
                Filename.concat
                  (Filename.dirname Sys.executable_name)
                  "signal_fixture.exe"
              in
              List.iter
                (fun command ->
                  let child =
                    match
                      Eta_process.Child.spawn ~sw ~clock:env#clock ~mgr:env#process_mgr
                        ~argv:((fixture :: command) @ [ "--config"; file ])
                        ~grace:(Eta.Duration.ms 50) ~stdout:Eta_process.Child.Pipe
                        ~stderr:Eta_process.Child.Pipe ~fds:[] ()
                    with
                    | Ok child -> child
                    | Error _ -> Alcotest.fail "invalid fixture spawn"
                  in
                  let status =
                    Eio.Time.with_timeout_exn env#clock 5. (fun () ->
                        Eta_process.Child.await child)
                  in
                  Alcotest.(check bool)
                    "reader rejects oversized file" true
                    (match status with Eta_process.Child.Exited 2 -> true | _ -> false);
                  let errors =
                    Eio.Flow.read_all (Option.get (Eta_process.Child.stderr child))
                  in
                  expect_part errors "file exceeds byte limit";
                  ignore (Eta_process.Child.stop child))
                [ []; [ "config"; "check" ] ])))

let test_door2_service_args () =
  let open Cmdliner in
  let flag name = Arg.(value & opt string "unset" & info [ name ]) in
  let service_args =
    Term.(
      const (fun transcribe translate -> (transcribe, translate))
      $ flag "ptt-transcribe-keysym" $ flag "ptt-translate-keysym")
  in
  Eta_test.run (fun base _ ->
      let seen = ref [] in
      let output = Buffer.create 80 and errors = Buffer.create 80 in
      let invoke argv =
        run_for_test_with_args ~service_args ~env:base ~name:"demo" ~config ~pp_err
          ~getenv
          ~read:(fun _ -> Ok good)
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~stderr:(fun text -> Buffer.add_string errors text)
          ~stdout:(fun text -> Buffer.add_string output text)
          ~argv
          (fun env source settings (transcribe, translate) _sw ->
            ignore env.Env.base#clock;
            seen := (source, settings.port, transcribe, translate) :: !seen;
            Ok ())
      in
      check_int "^napp-ytqk bare overrides" 0
        (invoke
           [| "demo"; "--ptt-transcribe-keysym"; "F10"; "--ptt-translate-keysym"; "F11" |]);
      check_int "^napp-ytqk named service" 0
        (invoke [| "demo"; "run"; "--ptt-transcribe-keysym"; "F12" |]);
      Alcotest.(check (list (pair int (pair string string))))
        "both invocations receive typed values"
        [ (42, ("F12", "unset")); (42, ("F10", "F11")) ]
        (List.map (fun (_source, port, a, b) -> (port, (a, b))) !seen);
      check_string "no diagnostics" "" (Buffer.contents errors))

(* ^napp-x11e: one Env builds terms, each execution receives a fresh owned switch. *)
let test_door2_commands () =
  let open Cmdliner in
  Eta_test.run (fun base _ ->
      let seen = ref [] and releases = ref 0 in
      let errors = Buffer.create 80 in
      let code argv =
        run_for_test_with_args ~service_args:(Term.const ()) ~env:base ~name:"demo"
          ~config ~pp_err ~getenv
          ~read:(fun _ -> Alcotest.fail "an extra command must not read service config")
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~stderr:(fun text -> Buffer.add_string errors text)
          ~stdout:ignore ~argv
          ~commands_with_env:(fun door_env run_owned ->
            let term =
              Term.(
                const (fun value () ->
                    run_owned (fun sw ->
                        Eio.Switch.on_release sw (fun () -> incr releases);
                        ignore door_env.Env.base#clock;
                        seen := value :: !seen;
                        if value = "fail" then Error (`Problem "verb failed") else Ok ()))
                $ Arg.(required & pos 0 (some string) None & info []))
            in
            [ Cmd.v (Cmd.info "echo") term ])
          (fun _ _ _ _ _ -> Alcotest.fail "extra command must not serve")
      in
      check_int "^napp-x11e success" 0 (code [| "demo"; "echo"; "yes" |]);
      check_int "^napp-x11e typed error" 1 (code [| "demo"; "echo"; "fail" |]);
      check_int "^napp-x11e malformed args" 2 (code [| "demo"; "echo" |]);
      Alcotest.(check (list string)) "only valid terms execute" [ "fail"; "yes" ] !seen;
      check_int "owned switch releases on both outcomes" 2 !releases;
      expect_part (Buffer.contents errors) "verb failed")

(* ^napp-ersz: file selection, strict missing, explicit override and source reach
   both run and config check through the same reader seam. *)
let test_door2_source_policy () =
  Eta_test.run (fun base _ ->
      let seen = ref [] and validated = ref [] and prompt_paths = ref [] in
      let out = Buffer.create 80 and err = Buffer.create 80 in
      let read path =
        seen := path :: !seen;
        if Filename.basename path = "stt.toml" then Ok good
        else if path = "/somewhere/app/override.toml" then Ok good
        else Error `Missing
      in
      let invoke ?(missing = `Required) argv =
        run_for_test_with_args ~service_args:(Cmdliner.Term.const ()) ~env:base
          ~name:"demo" ~config ~pp_err ~getenv ~read ~missing ~config_file:"stt.toml"
          ~validate_source:(fun _ source _ ->
            validated := source :: !validated;
            let path = match source with `Default p | `Explicit p -> p in
            prompt_paths :=
              Filename.concat (Filename.dirname path) "prompts/foo.md" :: !prompt_paths;
            Ok ())
          ~journal:
            (Eta_observability.Logger.Memory.reporter
               (Eta_observability.Logger.Memory.create ()))
          ~stdout:(fun text -> Buffer.add_string out text)
          ~stderr:(fun text -> Buffer.add_string err text)
          ~argv
          (fun _ source _ () _ ->
            validated := source :: !validated;
            Ok ())
      in
      check_int "^napp-ersz default" 0 (invoke [| "demo" |]);
      expect_part (List.hd !seen) "/demo/stt.toml";
      check_int "^napp-ersz explicit" 0
        (invoke [| "demo"; "--config"; "/somewhere/app/override.toml" |]);
      Alcotest.(check bool)
        "explicit source reaches program" true
        (List.mem (`Explicit "/somewhere/app/override.toml") !validated);
      Alcotest.(check bool)
        "source anchors relative prompt paths" true
        (List.mem "/somewhere/app/prompts/foo.md" !prompt_paths);
      check_int "^napp-ersz check uses same reader" 0
        (invoke [| "demo"; "config"; "check" |]);
      check_int "^napp-ersz required missing" 2
        (invoke [| "demo"; "--config"; "/missing.toml" |]);
      expect_part (Buffer.contents err) "/missing.toml: no such file";
      check_int "^napp-ersz required default missing" 2
        (run_for_test_with_args ~service_args:(Cmdliner.Term.const ()) ~env:base
           ~name:"demo" ~config ~pp_err ~getenv
           ~read:(fun _ -> Error `Missing)
           ~missing:`Required ~config_file:"stt.toml"
           ~journal:
             (Eta_observability.Logger.Memory.reporter
                (Eta_observability.Logger.Memory.create ()))
           ~stdout:ignore
           ~stderr:(fun text -> Buffer.add_string err text)
           ~argv:[| "demo" |]
           (fun _ _ _ () _ -> Alcotest.fail "missing file must not run"));
      expect_part (Buffer.contents err) "/demo/stt.toml: no such file")

let test_door2_bounded_reader () =
  let file = Filename.temp_file "eta-door2-" ".toml" in
  let fifo = file ^ "-fifo" in
  Unix.mkfifo fifo 0o600;
  Fun.protect
    ~finally:(fun () ->
      Sys.remove fifo;
      Sys.remove file)
    (fun () ->
      let out = open_out file in
      output_string out "12345";
      close_out out;
      Eio_main.run (fun env ->
          let read path = Config.read_regular ~max_bytes:4 Eio.Path.(env#fs / path) in
          Alcotest.(check bool)
            "^napp-ersz oversized regular file" true
            (match read file with Error (`Unreadable _) -> true | _ -> false);
          Alcotest.(check bool)
            "^napp-ersz reject directory" true
            (match read (Filename.dirname file) with
            | Error (`Unreadable _) -> true
            | _ -> false);
          Alcotest.(check bool)
            "^napp-ersz reject FIFO without opening" true
            (match read fifo with Error (`Unreadable _) -> true | _ -> false);
          Alcotest.(check bool)
            "^napp-ersz missing" true
            (match read (file ^ "-absent") with Error `Missing -> true | _ -> false);
          Alcotest.(check bool)
            "^napp-ersz exact boundary" true
            (match Config.read_regular ~max_bytes:5 Eio.Path.(env#fs / file) with
            | Ok "12345" -> true
            | _ -> false)))

let () =
  Alcotest.run "eta_app"
    [
      ( "door",
        [
          Alcotest.test_case "^napp-ytqk typed service args" `Quick
            test_door2_service_args;
          Alcotest.test_case "^napp-x11e Eio commands" `Quick test_door2_commands;
          Alcotest.test_case "^napp-x11e real SIGTERM extra command" `Quick
            test_door2_real_signal_extra;
          Alcotest.test_case "^napp-ersz source policy" `Quick test_door2_source_policy;
          Alcotest.test_case "^napp-ersz production reader" `Quick
            test_door2_production_reader;
          Alcotest.test_case "^napp-ersz bounded regular reader" `Quick
            test_door2_bounded_reader;
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
          Alcotest.test_case "^napp-9x0s absent config" `Quick test_absent_default_config;
          Alcotest.test_case "^napp-9x0s absent default path, real Door" `Quick
            test_default_path_absent;
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
          Alcotest.test_case "^napp-wf22 config group subcommand" `Quick
            test_config_commands;
          Alcotest.test_case "^napp-d5e4 service command name" `Quick test_service_command;
          Alcotest.test_case "^napp-d5e4 consumer run beside serve" `Quick
            test_service_command_coexists;
          Alcotest.test_case "^napp-idii telemetry hook" `Quick test_telemetry_hook;
          Alcotest.test_case "^napp-idii raising telemetry hook" `Quick
            test_telemetry_defect;
          Alcotest.test_case "^napp-idii config check runs no hook" `Quick
            test_telemetry_check_path;
          Alcotest.test_case "^napp-2aa6 ^nnoschema-boxo CLI and IO errors" `Quick
            test_cli_and_io_errors;
          Alcotest.test_case "^napp-57qi run runs the validator" `Quick test_run_validates;
          Alcotest.test_case "^napp-idii telemetry flush on SIGTERM" `Quick
            test_real_signal_telemetry;
          Alcotest.test_case "^notel-1stb OTLP drain on SIGTERM" `Quick
            test_real_signal_otlp;
          Alcotest.test_case "^notel-1stb shutdown in a release hook on SIGTERM" `Quick
            test_real_signal_otlp_shutdown;
          Alcotest.test_case "nlimit-s3f4 real SIGTERM" `Quick
            (test_real_signal Sys.sigterm);
          Alcotest.test_case "nlimit-s3f4 real SIGINT" `Quick
            (test_real_signal Sys.sigint);
        ] );
    ]
