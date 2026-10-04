(* Row 48 (docs/issues/caps/01-caps.md): capabilities in signatures. Each case names the
   story it covers. The compile-time half — forged and excluded capabilities, and
   portability — is in compile_fail/, and the Semgrep gate over fixtures in gate/. *)
open Ox_caps

let check_bool = Alcotest.(check bool)
let check_int = Alcotest.(check int)
let check_string = Alcotest.(check string)

(* ^ncaps-sojd: a signature lists what a function may touch as an object row; any
   powerbox with at least those capabilities is accepted, and the body can use nothing
   else. *)
let needs_env_and_time ~(caps : < Cap.env ; Cap.time ; .. >) =
  (Cap_sys.getenv_opt ~caps "OX_CAPS_TEST_UNSET", Cap_unix.time ~caps ())

let rows_compose () =
  let powerbox = Ox_test.powerbox () in
  let narrowed = (powerbox :> < Cap.env ; Cap.time >) in
  let unset, now = needs_env_and_time ~caps:powerbox in
  check_bool "full powerbox accepted" true (unset = None && now > 0.);
  let unset, now = needs_env_and_time ~caps:narrowed in
  check_bool "narrowed powerbox accepted" true (unset = None && now > 0.);
  let (_ : Cap.process) = (powerbox :> Cap.process)
  and (_ : Cap.console) = (powerbox :> Cap.console)
  and (_ : Cap.fs) = (powerbox :> Cap.fs)
  and (_ : Cap.no_caps) = (powerbox :> Cap.no_caps) in
  ()

(* ^ncaps-0mvw: the Door mints the powerbox and hands it to the program in its Env and to
   the commands built with the Door's Env; nothing else in the program constructs one. *)
let door_hands_the_powerbox () =
  Ox_test.run (fun env _ ->
      let seen = ref [] in
      let program (door_env : _ Ox_app.Env.t) () _sw =
        let narrowed = (door_env.caps :> < Cap.env >) in
        seen := "program" :: !seen;
        match Cap_sys.getenv_opt ~caps:narrowed "OX_CAPS_TEST_UNSET" with
        | None -> Ok ()
        | Some _ -> Error `Unexpected
      in
      let config_commands_with_env (door_env : _ Ox_app.Env.t) =
        let open Cmdliner in
        [
          Cmd.v (Cmd.info "caps")
            Term.(
              const (fun () () ->
                  let (_ : < Cap.stdout >) = (door_env.caps :> < Cap.stdout >) in
                  seen := "config caps" :: !seen;
                  0)
              $ const ());
        ]
      in
      let invoke argv =
        Ox_app.run_for_test_with_args ~config_commands_with_env
          ~service_args:(Cmdliner.Term.const ()) ~env ~name:"demo"
          ~config:Ox_app.Config.none
          ~pp_err:(fun fmt `Unexpected -> Format.pp_print_string fmt "unexpected")
          ~getenv:(fun _ -> None)
          ~read:(fun _ -> Error `Missing)
          ~journal:
            (Ox_observability.Logger.Memory.reporter
               (Ox_observability.Logger.Memory.create ()))
          ~stdout:ignore ~stderr:ignore ~argv
          (fun door_env _source () () sw -> program door_env () sw)
      in
      check_int "program ran" 0 (invoke [| "demo" |]);
      check_int "config command ran" 0 (invoke [| "demo"; "config"; "caps" |]);
      Alcotest.(check (list string))
        "both received the Door's powerbox" [ "config caps"; "program" ] !seen)

(* ^ncaps-4btv: each wrapper is the raw call behind its capability. *)
let wrappers_are_the_raw_calls () =
  let caps = Ox_test.powerbox () in
  let path = Cap_stdlib.Filename.temp_file ~caps "ox-caps-" ".txt" in
  let out = Cap_stdlib.open_out_bin ~caps path in
  output_string out "written through Cap.fs_write";
  close_out out;
  let read = Cap_stdlib.In_channel.with_open_bin ~caps path In_channel.input_all in
  check_string "fs_read sees what fs_write wrote" "written through Cap.fs_write" read;
  (* ^pcaps-pdn5: a listener lockfile needs write-only access for lockf, not fs_read. *)
  let fd = Cap_unix.openfile_write ~caps path [ Unix.O_CLOEXEC ] 0 in
  Unix.lockf fd Unix.F_TLOCK 0;
  Unix.close fd;
  check_bool "write-only openfile refuses read modes" true
    (match Cap_unix.openfile_write ~caps path [ Unix.O_RDWR ] 0 with
    | exception Invalid_argument _ -> true
    | fd ->
        Unix.close fd;
        false);
  let dir = Filename.dirname path in
  check_bool "readdir lists it" true
    (Array.mem (Filename.basename path) (Cap_sys.readdir ~caps dir));
  Cap_sys.remove ~caps path;
  check_bool "remove removed it" false (Sys.file_exists path);
  check_int "urandom returns the bytes asked for" 16
    (String.length (Cap_sys.urandom ~caps 16));
  check_bool "system runs a program" true (Cap_unix.system ~caps "true" = Unix.WEXITED 0);
  check_bool "getenv_opt agrees with the environment" true
    (Cap_sys.getenv_opt ~caps "PATH" = Sys.getenv_opt "PATH");
  let null = Cap_unix.open_dev_null ~caps () in
  check_int "dev_null takes writes" 3 (Unix.write_substring null "abc" 0 3);
  Unix.close null;
  let (_ : Random.State.t) = Cap_stdlib.Random.make_self_init ~caps () in
  ()

(* Rows 45-47's risk for this row: Rate_limiter.run and Resource.use_in_scope take
   [@ local] closures. A capability is an ordinary value, so such a closure captures it
   and calls a wrapper; and a wrapper partially applied to its capability is an ordinary
   closure that can be stored, as [~getenv:(Cap_sys.getenv_opt ~caps)] is
   (^ncaps-sojd ^ncaps-4btv). *)
let read_home ~(caps : < Cap.env ; .. >) () = Cap_sys.getenv_opt ~caps "HOME"

let local_closures_compose () =
  Ox_test.run (fun env sw ->
      let caps = Ox_test.powerbox () in
      let limiter =
        Ox.Rate_limiter.create ~sw ~clock:env#clock
          (Ox.Rate_limiter.Fixed_window { n = 1; per = Ox.Duration.seconds 1 })
      in
      let from_limiter = Ox.Rate_limiter.run limiter (fun () -> read_home ~caps ()) in
      let from_resource =
        Ox.Resource.use_in_scope ~sw (fun () -> read_home ~caps ()) (fun _ -> ())
      in
      let stored : string -> string option = Cap_sys.getenv_opt ~caps in
      check_bool "same answer through both local closures and a stored partial" true
        (from_limiter = from_resource && from_resource = stored "HOME"))

(* ^ncaps-x7z8 ^ncaps-jkku: ox_process says in its interface that spawning a child forks
   and execs; Eio's process manager stays the value that does the work, so the call
   takes both. Discarded output opens /dev/null, which also requires fs_write. *)
let spawn_needs_fork_exec_and_fs_write () =
  Ox_test.run (fun env sw ->
      let caps = (Ox_test.powerbox () :> < Cap.fork ; Cap.exec ; Cap.fs_write >) in
      match
        Ox_process.Child.spawn ~caps ~sw ~clock:env#clock ~mgr:env#process_mgr
          ~argv:[ "true" ] ~grace:(Ox.Duration.ms 100) ~fds:[] ()
      with
      | Error _ -> Alcotest.fail "spawn refused"
      | Ok child ->
          check_bool "the child ran" true
            (Ox_process.Child.await child = Ox_process.Child.Exited 0))

let () =
  Alcotest.run "ox_caps"
    [
      ( "caps",
        [
          Alcotest.test_case "ncaps-sojd rows compose and narrow" `Quick rows_compose;
          Alcotest.test_case "ncaps-0mvw the Door hands the powerbox" `Quick
            door_hands_the_powerbox;
          Alcotest.test_case "ncaps-4btv pcaps-pdn5 wrappers are the raw calls" `Quick
            wrappers_are_the_raw_calls;
          Alcotest.test_case "ncaps-4btv capabilities in local closures" `Quick
            local_closures_compose;
          Alcotest.test_case
            "ncaps-x7z8 ncaps-jkku spawn takes fork, exec, fs_write and mgr" `Quick
            spawn_needs_fork_exec_and_fs_write;
        ] );
    ]
