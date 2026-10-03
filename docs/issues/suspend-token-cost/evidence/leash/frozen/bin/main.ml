open Cmdliner
module P = Leash.Protocol
module Skill_install = Leash_cli_support.Skill_install
module Cap_stdlib = Ox_caps.Cap_stdlib
module Cap_sys = Ox_caps.Cap_sys

(* ^ncaps-4tjy: every command gets its capabilities from the Door's powerbox
   ([Ox_app.Env.caps], handed to the command builders below); nothing here touches the
   environment, the standard streams or a file except through them. *)

let obj fields = `Assoc fields
let str s = `String s

(* daily-azxe daily-6pde daily-3bwr: the same record and code table on both sides
   of the socket. Errors are always one compact JSON line, never affected by --pretty. *)
let make_error ?detail name message : P.error =
  let code =
    match P.Error_code.of_string name with
    | Ok code -> code
    | Error _ -> invalid_arg "unknown CLI error code"
  in
  P.make_error ?detail code ~message

let emit_error ~caps (error : P.error) =
  Cap_stdlib.prerr_endline ~caps (Yojson.Safe.to_string (P.yojson_of_error error));
  P.Error_code.exit_code error.code

let report ~caps ?detail code message = emit_error ~caps (make_error ?detail code message)
let usage ~caps message = report ~caps "usage" message
let failure ~caps message = report ~caps "internal" message
let invalid_playbook ~caps message = report ~caps "playbook-invalid" message

let protect ~caps run =
  try run () with
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | Unix.Unix_error ((Unix.EACCES | Unix.EPERM | Unix.EROFS), _, _) ->
      report ~caps "permission-denied"
        "permission denied while accessing a local resource"
  | Eio.Io (Eio.Fs.E (Eio.Fs.Permission_denied _), _) ->
      report ~caps "permission-denied"
        "permission denied while accessing a local resource"
  | _ ->
      failure ~caps "the command failed unexpectedly; no successful result was produced"

let send ?timeout_s ~base path request =
  let run () =
    Eio.Switch.run (fun sw ->
        let socket = Eio.Net.connect ~sw base#net (`Unix path) in
        let data = Yojson.Safe.to_string request ^ "\n" in
        Eio.Flow.copy_string data socket;
        let reader = Eio.Buf_read.of_flow ~max_size:8_388_608 socket in
        Eio.Buf_read.line reader)
  in
  match timeout_s with
  | None -> run ()
  | Some seconds -> Eio.Time.with_timeout_exn base#clock seconds run

let field key = function
  | `Assoc fields -> ( match List.assoc_opt key fields with Some x -> x | None -> `Null)
  | _ -> `Null

let cell = function
  | `String s -> s
  | `Int n -> string_of_int n
  | `Bool b -> string_of_bool b
  | `Null -> "-"
  | other -> Yojson.Safe.to_string other

let kind_cell key row =
  match field "page_kind" row with
  | `Assoc fields -> (
      match List.assoc_opt key fields with Some value -> cell value | None -> "-")
  | _ -> "-"

let table ~caps command result =
  let tabs = match field "tabs" result with `List xs -> xs | _ -> [] in
  match command with
  | "list" ->
      (* hand-r4t1: REASON is what the tab is waiting on the human for, "-" on every tab
         nobody is waiting on, so a human who stepped away can see what is asked.
         kind-tdrv: PAGE_KIND and KIND_SOURCE name the page outside a drive. *)
      Cap_stdlib.print_endline ~caps
        "LABEL\tURL\tTITLE\tPAGE_KIND\tKIND_SOURCE\tORIGIN\tAGE_S\tIDLE_S\tCLOSES_IN_S\tWITH_HUMAN";
      List.iter
        (fun row ->
          let cols =
            [
              cell (field "label" row);
              cell (field "url" row);
              cell (field "title" row);
              kind_cell "name" row;
              kind_cell "source" row;
              cell (field "origin" row);
              cell (field "age_s" row);
              cell (field "idle_s" row);
              cell (field "closes_in_s" row);
              cell (field "with_human" row);
            ]
          in
          Cap_stdlib.print_endline ~caps (String.concat "\t" cols))
        tabs
  | "snap" ->
      Cap_stdlib.printf ~caps "PAGE_KIND\t%s\tKIND_SOURCE\t%s\n" (kind_cell "name" result)
        (kind_cell "source" result);
      Cap_stdlib.print_endline ~caps "INDEX\tROLE\tNAME\tVALUE\tSTATE";
      (match field "rows" result with `List xs -> xs | _ -> [])
      |> List.iter (fun row ->
          Cap_stdlib.printf ~caps "%s\t%s\t%s\t%s\t%s\n"
            (cell (field "index" row))
            (cell (field "role" row))
            (cell (field "name" row))
            (cell (field "value" row))
            (match field "state" row with
            | `List xs -> String.concat "," (List.map cell xs)
            | _ -> ""))
  | _ -> ()

(* svc-hi4f: the options every command shares and the request fields it must not carry —
   the CLI's own, peeled off here so a command's table entry lists exactly what goes on
   the wire. *)
let cli_options = [ "pretty"; "table"; "config"; "socket"; "argument_file"; "stdin" ]

(* svc-o4wt svc-x8rp: --socket wins for one call; otherwise the CLI reads the same
   configuration the service does — --config, or $XDG_CONFIG_HOME/leash/config.toml — and
   the Door's rule decides whether an absent file is allowed (napp-9x0s): nothing at the
   default path is the defaults, so the client works before `leash config init` has run,
   while a --config path that is not there is an error naming it, exactly what the service
   reports. A file that is there and wrong is an error either way. *)
let load_config ~caps ~config =
  let source =
    Ox_app.Config.resolve ~name:"leash" ~config ~getenv:(Cap_sys.getenv_opt ~caps)
  in
  let read path =
    if not (Sys.file_exists path) then Error `Missing
    else
      try Ok (Cap_stdlib.In_channel.with_open_bin ~caps path In_channel.input_all)
      with Sys_error _ ->
        Error (`Unreadable "cannot read the configuration file; check permissions")
  in
  match
    Ox_app.Config.load
      ~spec:
        {
          Leash.Config.spec with
          of_yojson =
            (fun json ->
              match Leash.Config.decode_all ~getenv:(Cap_sys.getenv_opt ~caps) json with
              | Ok config -> Ok config
              | Error problems -> Error (Ox_app.Config.render_validation_errors problems));
        }
      ~getenv:(Cap_sys.getenv_opt ~caps) ~read ~source
  with
  | Ok config -> Ok config
  | Error (`Config message) ->
      let file = match source with `Explicit path | `Default path -> path in
      Error ("invalid configuration in " ^ file ^ ": " ^ message)

let configured_roots (config : Leash.Config.t) =
  List.map Leash.Config.Text.to_string config.skill.roots

let service_socket ~caps ~config ~socket =
  match socket with
  | Some path -> Ok path
  | None -> (
      match load_config ~caps ~config with
      | Error message -> Error message
      | Ok config ->
          let path = Leash.Config.Text.to_string config.control.socket in
          if String.contains path '$' then
            Error
              ("the control socket " ^ path
             ^ " does not resolve; set XDG_RUNTIME_DIR or pass --socket")
          else Ok path)

let secret_field name =
  let name = String.lowercase_ascii name in
  name = "api_key" || name = "openrouter_api_key" || name = "token"
  || name = "authorization"
  || String.ends_with ~suffix:"_api_key" name

let rec strip_secrets = function
  | `Assoc fields ->
      `Assoc
        (List.filter_map
           (fun (name, value) ->
             if secret_field name then None else Some (name, strip_secrets value))
           fields)
  | `List values -> `List (List.map strip_secrets values)
  | other -> other

let assoc_field key = function `Assoc fields -> List.assoc_opt key fields | _ -> None
let put key value fields = (key, value) :: List.remove_assoc key fields

(* daily-smli: the printed status never carries a key. Version and commit are the
   running binary's when the service omits them; key_present is a boolean derived from
   the models section, never a string. *)
let enrich_status ~caps ~roots body =
  match strip_secrets body with
  | `Assoc fields ->
      let home = Option.value ~default:"" (Cap_sys.getenv_opt ~caps "HOME") in
      let key_present =
        match assoc_field "models" (`Assoc fields) with
        | Some (`Assoc models) -> (
            match List.assoc_opt "configured" models with
            | Some (`Bool present) -> present
            | _ -> false)
        | _ -> false
      in
      let fields = put "skill" (Skill_install.status ~caps ~home ~roots) fields in
      let fields =
        match List.assoc_opt "version" fields with
        | Some (`String _) -> fields
        | _ -> put "version" (str Leash.version) fields
      in
      let fields =
        put "commit" (str Leash_cli_support.Leash_build_commit.commit) fields
      in
      obj (put "key_present" (`Bool key_present) fields)
  | other -> strip_secrets other

let leash_binary_present ~caps =
  match Cap_sys.getenv_opt ~caps "PATH" with
  | None -> false
  | Some path ->
      List.exists
        (fun dir -> dir <> "" && Sys.file_exists (Filename.concat dir "leash"))
        (String.split_on_char ':' path)

let systemctl_show base =
  try
    Ok
      (Eio.Process.parse_out base#process_mgr Eio.Buf_read.take_all
         [
           "systemctl";
           "--user";
           "show";
           "leash.service";
           "-p";
           "LoadState";
           "-p";
           "ActiveState";
           "-p";
           "SubState";
           "--no-pager";
         ])
  with
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | _ -> Error ()

let install_observation ~caps ~base =
  match Cap_sys.getenv_opt ~caps "LEASH_INSTALL_FIXTURE" with
  | Some fixture when fixture <> "" -> (
      try
        let text =
          Cap_stdlib.In_channel.with_open_bin ~caps fixture In_channel.input_all
        in
        Ok (Leash_cli_support.Install_state.of_fixture text)
      with
      | Eio.Cancel.Cancelled _ as exn -> raise exn
      | _ -> Error ())
  | _ -> (
      match systemctl_show base with
      | Error () -> Error ()
      | Ok text ->
          Ok
            (Leash_cli_support.Install_state.of_systemctl
               ~binary_present:(leash_binary_present ~caps) text))

(* daily-c4cl: every transport client uses the same install-state diagnosis.
   A fixture file keeps regression checks off the operator's systemd. *)
let status_down ~caps ~base path =
  let socket = ("socket", str path) in
  let detail ?obs () =
    let flags =
      match obs with
      | None -> []
      | Some obs ->
          [
            ("unit", `Bool (Leash_cli_support.Install_state.unit_present obs));
            ("binary", `Bool obs.binary_present);
          ]
    in
    obj (socket :: flags)
  in
  match install_observation ~caps ~base with
  | Error () ->
      report ~caps ~detail:(detail ()) "service-unreachable"
        ("cannot reach the Leash service at " ^ path)
  | Ok obs ->
      let diagnosis = Leash_cli_support.Install_state.diagnose obs in
      let code = Leash_cli_support.Install_state.code diagnosis in
      let message =
        if code = "service-unreachable" then "cannot reach the Leash service at " ^ path
        else Leash_cli_support.Install_state.message diagnosis obs
      in
      report ~caps ~detail:(detail ~obs ()) code message

(* One request to the service and its decoded reply; an error is the exit status to
   return after saying what went wrong. *)
let exchange ~caps ~send ~base ~config ~socket request =
  match service_socket ~caps ~config ~socket with
  | Error why -> Error (report ~caps "config-invalid" why)
  | Ok path -> (
      let detail = obj [ ("socket", str path) ] in
      let unreachable () = Error (status_down ~caps ~base path) in
      let denied () =
        Error
          (report ~caps ~detail "socket-permission"
             ("cannot access the control socket at " ^ path))
      in
      try
        let raw = Yojson.Safe.from_string (send path request) in
        match P.decode_reply raw with
        | Error _ ->
            Error
              (report ~caps ~detail "invalid-response"
                 "the service returned an invalid reply")
        | Ok reply -> Ok reply
      with
      | Unix.Unix_error ((Unix.EACCES | Unix.EPERM), _, _) -> denied ()
      | Eio.Io (Eio.Fs.E (Eio.Fs.Permission_denied _), _) -> denied ()
      | Unix.Unix_error _ | Eio.Io _ | End_of_file -> unreachable ()
      | Eio.Time.Timeout ->
          Error (report ~caps ~detail "timeout" "the service request timed out")
      | Yojson.Json_error _ | Eio.Buf_read.Buffer_limit_exceeded ->
          Error
            (report ~caps ~detail "invalid-response"
               "the service returned unreadable JSON"))

(* fly-nolf fly-hc3l: --url is an explicit http(s) start; --max-steps is a positive
   executed-action cap. Both fail here, before a socket connect, as the L41 usage record.
   The host check matches the service: scheme, no userinfo, no control characters. *)
let http_start_url url =
  let start =
    if String.starts_with ~prefix:"https://" url then 8
    else if String.starts_with ~prefix:"http://" url then 7
    else String.length url
  in
  let rec stop i =
    if i = String.length url || String.contains "/?#" url.[i] then i else stop (i + 1)
  in
  let last = stop start in
  last > start
  && (not (String.contains (String.sub url start (last - start)) '@'))
  && not (String.exists (fun c -> Char.code c <= 32 || Char.code c = 127) url)

let url_usage =
  "--url must be an http:// or https:// URL with no userinfo. Example: leash drive 'Open \
   Travel and return the visible titles and prices' --url https://books.toscrape.com/"

let max_steps_usage =
  "--max-steps must be a positive integer (default 15). Example: leash drive 'Complete \
   this page search and open the matching result' --tab TAB --max-steps 15"

let drive_request_options options =
  let options =
    match List.assoc_opt "url" options with
    | None -> Ok options
    | Some (`String url) when http_start_url url ->
        Ok (("start_url", `String url) :: List.remove_assoc "url" options)
    | Some _ -> Error url_usage
  in
  match options with
  | Error _ as error -> error
  | Ok options -> (
      (* trace-qe8c: output belongs to the caller, not the service cwd. *)
      let options =
        List.map
          (function
            | "out", `String path when Filename.is_relative path ->
                ("out", `String (Filename.concat (Sys.getcwd ()) path))
            | field -> field)
          options
      in
      match List.assoc_opt "max_steps" options with
      | None -> Ok options
      | Some (`Int n) when n > 0 -> Ok options
      | Some _ -> Error max_steps_usage)

(* field-5sdo: fill text may come from the argument, a file, or stdin. The read stops
   at the service's 64 KiB bound; the value is not printed here. *)
let fill_limit = 65_536

let read_bounded ic =
  let limit = fill_limit + 1 in
  let buf = Bytes.create limit in
  let rec read_all off =
    if off = limit then off
    else
      let n = In_channel.input ic buf off (limit - off) in
      if n = 0 then off else read_all (off + n)
  in
  let n = read_all 0 in
  if n > fill_limit then Error `Too_large else Ok (Bytes.sub_string buf 0 n)

let read_fill_file ~caps path =
  if not (Sys.file_exists path) then Error (`Missing path)
  else
    try Cap_stdlib.In_channel.with_open_bin ~caps path read_bounded with
    | Eio.Cancel.Cancelled _ as exn -> raise exn
    | Unix.Unix_error ((Unix.EACCES | Unix.EPERM | Unix.EROFS), _, _) -> Error `Denied
    | Eio.Io (Eio.Fs.E (Eio.Fs.Permission_denied _), _) -> Error `Denied
    | Sys_error _ -> Error (`Missing path)

let rec perform ~caps ~send ~base command fields positionals options =
  match (command, positionals) with
  (* hard-xg6y hard-ovbx hard-vq5s: `net TAB` lists; `net TAB body ID` and `net TAB request
     ID` are commands of their own on the wire. *)
  | "net", [ tab; (("body" | "request") as part); id ] ->
      perform ~caps ~send ~base ("net_" ^ part) [ "tab"; "id" ] [ tab; id ] options
  | "net", [ _; verb; _ ] -> usage ~caps ("net takes body or request, not " ^ verb)
  | "net", [ _; _ ] -> usage ~caps "net takes body ID or request ID after the tab"
  | "net", _ :: _ :: _ :: _ ->
      usage ~caps "net takes a tab, and optionally body or request with an ID"
  (* hard-o3za: the files are the trailing positionals. *)
  | "upload", tab :: snapshot :: index :: (_ :: _ as paths) ->
      perform_wire ~caps ~send ~base command
        [ "tab"; "snapshot"; "index" ]
        [ tab; snapshot; index ]
        (Some ("paths", `List (List.map str paths)) :: options)
  | "drive", _ when List.exists (function Some ("secret", _) -> true | _ -> false) options ->
      let specs = List.find_map (function Some ("secret", `List specs) -> Some specs | _ -> None) options |> Option.value ~default:[] in
      let rec resolve acc = function
        | [] -> Ok (List.rev acc)
        | `String spec :: rest -> (match String.index_opt spec '=' with
            | None -> Error "--secret requires NAME=@file or NAME=-"
            | Some split ->
                let name = String.sub spec 0 split in
                let source = String.sub spec (split + 1) (String.length spec - split - 1) in
                if name = "" || List.exists (fun (key, _) -> key = name) acc then Error "secret names must be nonempty and unique"
                else
                  let input = if source = "-" then read_bounded (Cap_stdlib.stdin ~caps)
                    else if String.starts_with ~prefix:"@" source then read_fill_file ~caps (String.sub source 1 (String.length source - 1))
                    else Error (`Missing "secret source") in
                  (match input with
                  | Error _ -> Error "cannot read secret source (expected NAME=@file or NAME=-, at most 64 KiB)"
                  | Ok value ->
                      let value = if String.ends_with ~suffix:"\n" value then String.sub value 0 (String.length value - 1) else value in
                      resolve ((name, value) :: acc) rest))
        | _ -> Error "invalid secret option" in
      (match resolve [] specs with
      | Error why -> usage ~caps why
      | Ok pairs ->
          let options = List.filter (function Some ("secret", _) -> false | _ -> true) options in
          perform ~base ~caps ~send "drive" fields positionals
            (Some ("secrets", `List (List.map (fun (key, value) -> `List [`String key; `String value]) pairs)) :: options))
  | "fill", _ -> (
      let present key =
        List.find_map
          (function Some (name, value) when name = key -> Some value | _ -> None)
          options
      in
      let positional =
        if List.length positionals >= 4 then List.nth positionals 3 else ""
      in
      let file =
        match present "argument_file" with Some (`String path) -> Some path | _ -> None
      in
      let from_stdin =
        match present "stdin" with Some (`Bool true) -> true | _ -> false
      in
      let from_arg = String.trim positional <> "" in
      let sources =
        (if from_arg then 1 else 0)
        + (if Option.is_some file then 1 else 0)
        + if from_stdin then 1 else 0
      in
      if sources = 0 then
        usage ~caps "fill: TEXT is missing; usage: fill TAB SNAPSHOT INDEX TEXT"
      else if sources > 1 then
        usage ~caps "fill: give TEXT, --argument-file or --stdin, not more than one"
      else
        let read =
          if from_stdin then read_bounded (Cap_stdlib.stdin ~caps)
          else if from_arg then Ok positional
          else read_fill_file ~caps (Option.get file)
        in
        match read with
        | Error `Too_large -> report ~caps "too-large" "fill text is over 64 KiB"
        | Error `Denied ->
            report ~caps "permission-denied" "permission denied while reading fill text"
        | Error (`Missing path) ->
            usage ~caps
              ("fill: cannot read " ^ path ^ "; pass an existing file to --argument-file")
        | Ok text ->
            let positionals =
              if List.length positionals >= 4 then
                List.mapi (fun i value -> if i = 3 then text else value) positionals
              else positionals @ [ text ]
            in
            let fields =
              if List.exists (( = ) "text") fields then fields else fields @ [ "text" ]
            in
            perform_wire ~caps ~send ~base command fields positionals options)
  | _ -> perform_wire ~caps ~send ~base command fields positionals options

and perform_wire ~caps ~send ~base command fields positionals options =
  let actual = List.length positionals in
  let options = List.filter_map Fun.id options in
  let cli = List.filter (fun (name, _) -> List.mem name cli_options) options in
  let request = List.filter (fun (name, _) -> not (List.mem name cli_options)) options in
  let flag name =
    match List.assoc_opt name cli with Some (`Bool true) -> true | _ -> false
  in
  let text name =
    match List.assoc_opt name cli with Some (`String value) -> Some value | _ -> None
  in
  let pretty = flag "pretty" and use_table = flag "table" in
  if use_table && pretty then usage ~caps "--table and --pretty cannot both be given"
  else
    let encode_pos key value =
      if List.mem key [ "index"; "option" ] then
        match int_of_string_opt value with
        | Some number -> Ok (key, `Int number)
        | None -> Error (key ^ " must be an integer")
      else Ok (key, str value)
    in
    let fields =
      List.map2 encode_pos (List.filteri (fun n _ -> n < actual) fields) positionals
    in
    let rec collect = function
      | [] -> Ok []
      | Error e :: _ -> Error e
      | Ok x :: xs -> Result.map (fun tail -> x :: tail) (collect xs)
    in
    match collect fields with
    | Error why -> usage ~caps why
    | Ok fields -> (
        let options =
          try
            Ok
              (List.map
                 (fun (key, value) ->
                   if List.mem key [ "argument"; "until" ] then
                     match value with
                     | `String text -> (key, Yojson.Safe.from_string text)
                     | _ -> assert false
                   else (key, value))
                 request)
          with Yojson.Json_error why -> Error ("invalid JSON option: " ^ why)
        in
        match options with
        | Error why -> usage ~caps why
        | Ok options -> (
            let options =
              if command <> "wait" then options
              else
                let condition_names =
                  [ "url_prefix"; "text"; "index_gone"; "dialog"; "changed_since" ]
                in
                let conditions, rest =
                  List.partition (fun (key, _) -> List.mem key condition_names) options
                in
                let previous =
                  match List.assoc_opt "until" rest with
                  | Some (`Assoc fields) ->
                      List.filter
                        (fun (key, _) -> not (List.mem_assoc key conditions))
                        fields
                  | _ -> []
                in
                let rest = List.remove_assoc "until" rest in
                let timeout =
                  match List.assoc_opt "timeout" rest with
                  | Some value when not (List.mem_assoc "timeout_ms" rest) ->
                      [ ("timeout_ms", value) ]
                  | _ -> []
                in
                let rest = List.remove_assoc "timeout" rest in
                (("until", obj (conditions @ previous)) :: timeout) @ rest
            in
            let prepared =
              if command <> "drive" then Ok options else drive_request_options options
            in
            match prepared with
            | Error why -> usage ~caps why
            | Ok options -> (
                let args = obj (fields @ options) in
                match P.command_of_args ~cmd:command args with
                | Error why -> usage ~caps why
                | Ok decoded -> (
                    let request = P.encode_request P.{ command = decoded } in
                    match
                      exchange ~caps ~send ~base ~config:(text "config")
                        ~socket:(text "socket") request
                    with
                    | Error status -> status
                    | Ok (P.Failure error) -> emit_error ~caps error
                    | Ok (P.Success body) -> (
                        let roots =
                          if command <> "status" then Ok []
                          else
                            Result.map configured_roots
                              (load_config ~caps ~config:(text "config"))
                        in
                        match roots with
                        | Error message -> report ~caps "config-invalid" message
                        | Ok roots ->
                            let body =
                              if command <> "status" then body
                              else enrich_status ~caps ~roots body
                            in
                            if
                              command = "status"
                              && assoc_field "chrome" body = Some (`String "restarting")
                            then
                              let body =
                                match body with
                                | `Assoc fields -> obj (put "pid" `Null fields)
                                | other -> other
                              in
                              report ~caps ~detail:body "service-restarting"
                                "Chrome is restarting"
                            else (
                              if use_table then table ~caps command body
                              else
                                Cap_stdlib.print_endline ~caps
                                  (if pretty then Yojson.Safe.pretty_to_string body
                                   else Yojson.Safe.to_string body);
                              0))))))

(* svc-hi4f: the table is the CLI's contract. Every command names its positionals in the
   protocol's order — TAB, SNAPSHOT, INDEX — and lists exactly the options it takes, so
   `leash <command> --help` shows the whole call. The four shared options go on every
   command; --table only on the two that render one. *)
type option_kind = Str | Int | Float | Bool | Json | Strings | Pairs

(* [Strings] is the repeated mission-expectation option [leash run] will carry
   (run-4j1v), declared here so the command lands as one table entry once the Door's name
   is free. *)
type option_ = { name : string; kind : option_kind; docv : string; doc : string }
type positional = { field : string; docv : string; optional : bool; many : bool }

let opt name kind docv doc = { name; kind; docv; doc }

(* svc-hi4f run-4j1v: an option a caller repeats — the mission's own expectations — becomes
   one JSON array on the wire. *)
let opt_list name kind docv doc = { name; kind; docv; doc }
let pos field docv = { field; docv; optional = false; many = false }
let pos_opt field docv = { field; docv; optional = true; many = false }

(* hard-o3za: the trailing positionals, one or more (the files `upload` sets). *)
let pos_many field docv = { field; docv; optional = false; many = true }
let pretty_opt = opt "pretty" Bool "" "Indent JSON output."

let table_opt =
  opt "table" Bool ""
    "Render rows as a table. list adds PAGE_KIND and KIND_SOURCE. For snap this omits \
     the snapshot id and prints the page kind above the rows; omit --table to get the id \
     needed by row actions."

let config_opt =
  opt "config" Str "FILE" "TOML configuration file the control socket is read from."

let socket_opt = opt "socket" Str "PATH" "Control socket path; overrides control.socket."
let shared_options = [ pretty_opt; config_opt; socket_opt ]

let option_term { name; kind; docv; doc } =
  let long = String.map (fun c -> if c = '_' then '-' else c) name in
  let arg_info = Arg.info ?docv:(if docv = "" then None else Some docv) ~doc [ long ] in
  match kind with
  | Bool ->
      Term.(
        const (fun value -> if value then Some (name, `Bool true) else None)
        $ Arg.(value & flag & arg_info))
  | Int ->
      Term.(
        const (Option.map (fun number -> (name, `Int number)))
        $ Arg.(value & opt (some int) None & arg_info))
  | Float ->
      Term.(
        const (Option.map (fun number -> (name, `Float number)))
        $ Arg.(value & opt (some float) None & arg_info))
  | Str ->
      Term.(
        const (Option.map (fun value -> (name, str value)))
        $ Arg.(value & opt (some string) None & arg_info))
  | Json ->
      Term.(
        const (Option.map (fun value -> (name, str value)))
        $ Arg.(value & opt (some string) None & arg_info))
  | Pairs ->
      (* extr-mp5z: --arg K=V, repeated, is the wire's `args` object of strings. *)
      Term.(
        const (fun pairs ->
            if pairs = [] then None
            else
              Some
                ( "args",
                  `Assoc (List.map (fun (key, value) -> (key, `String value)) pairs) ))
        $ Arg.(value & opt_all (pair ~sep:'=' string string) [] & arg_info))
  | Strings ->
      Term.(
        const (fun values ->
            if values = [] then None
            else Some (name, `List (List.map (fun value -> `String value) values)))
        $ Arg.(value & opt_all string [] & arg_info))

let positional_term positionals =
  List.fold_left
    (fun term (index, spec) ->
      let arg =
        if spec.many then
          Term.(
            const Fun.id
            $ Arg.(value & pos_right (index - 1) string [] & info [] ~docv:spec.docv))
        else
          Term.(
            const (fun value -> Option.to_list value)
            $ Arg.(value & pos index (some string) None & info [] ~docv:spec.docv))
      in
      Term.(const ( @ ) $ term $ arg))
    (Term.const [])
    (List.mapi (fun index spec -> (index, spec)) positionals)

(* field-uqvp: a missing or blank positional is a usage error that names the argument
   and the synopsis, not a Cmdliner parse failure. An empty shell variable is blank. *)
let positional_blank s = String.trim s = ""

let synopsis name specs =
  String.concat " " (name :: List.map (fun spec -> spec.docv) specs)

let missing_positional specs values =
  let rec go i = function
    | [] -> None
    | spec :: rest when spec.many ->
        let tail = List.filteri (fun j _ -> j >= i) values in
        if tail = [] || List.exists positional_blank tail then Some spec else None
    | spec :: rest when spec.optional -> go (i + 1) rest
    | spec :: rest -> (
        match List.nth_opt values i with
        | Some s when not (positional_blank s) -> go (i + 1) rest
        | _ -> Some spec)
  in
  go 0 specs

let usage_missing ~caps name specs spec =
  usage ~caps
    (Printf.sprintf "%s: %s is missing; usage: %s" name spec.docv (synopsis name specs))

let command ~caps ~send ~base ~run_owned ?wire ?docs ?(man = []) name doc positionals
    options examples =
  (* hdoc-vqj7: parsing remains a JSON usage error, but the synopsis is not optional. *)
  let man =
    if name = "press" then
      [
        `S "SYNOPSIS";
        `P "$(mname) $(b,press) [$(i,OPTION)]… $(i,TAB) $(i,SNAPSHOT) $(i,KEY)";
      ]
      @ man
    else man
  in
  let wire = Option.value ~default:name wire in
  let fields = List.map (fun spec -> spec.field) positionals in
  let collected =
    List.fold_left
      (fun term spec -> Term.(const (fun xs x -> xs @ [ x ]) $ term $ option_term spec))
      (Term.const []) options
  in
  Cmd.v
    (Cli_help.command_info ?docs ~man name ~doc ~examples)
    Term.(
      const (fun args opts () ->
          run_owned (fun _sw ->
              protect ~caps (fun () ->
                  match missing_positional positionals args with
                  | Some spec -> usage_missing ~caps name positionals spec
                  | None -> perform ~caps ~send ~base wire fields args opts)))
      $ positional_term positionals $ collected)

(* run-tcuz run-dbji run-ykq4: these authoring commands need no service. *)
let playbook_command ~caps ~send ~base ~run_owned =
  let owned run = run_owned (fun _sw -> protect ~caps run) in
  let output ?code = function
    | Error message -> invalid_playbook ~caps message
    | Ok book ->
        Cap_stdlib.print_endline ~caps
          (Yojson.Safe.pretty_to_string (Leash.Playbook.inspect ?code book));
        0
  in
  let name = Arg.(required & pos 0 (some string) None & info [] ~docv:"NAME") in
  let file = Arg.(required & pos 0 (some string) None & info [] ~docv:"FILE") in
  let list =
    Cmd.v
      (Cli_help.local_info ~docs:"INSTALLED PLAYBOOKS" "list"
         ~doc:"List validated installed site playbooks."
         ~examples:[ "leash playbook list" ])
      Term.(
        const (fun () () ->
            owned (fun () ->
                match Leash.Playbook.list ~caps () with
                | Error message -> invalid_playbook ~caps message
                | Ok books ->
                    List.iter
                      (fun (book : Leash.Playbook.loaded) ->
                        Cap_stdlib.printf ~caps "%s\t%s\n" book.playbook.site
                          book.playbook.description)
                      books;
                    0))
        $ const ())
  in
  let show =
    Cmd.v
      (Cli_help.local_info ~docs:"INSTALLED PLAYBOOKS" "show"
         ~doc:
           "Show a named installed playbook: scripts, their text and resolved checkers."
         ~examples:[ "leash playbook show books.toscrape.com" ])
      Term.(
        const (fun name () () ->
            owned (fun () -> output ~code:true (Leash.Playbook.show ~caps name)))
        $ name $ const ())
  in
  (* extr-lslp: the local checks — the file resolves, no escape, `returns` well formed,
     expectations resolve — are the loader's; the syntax check needs a page, so an
     installed playbook (named, not a path) is sent to the service, which compiles each
     script in a blank tab of its own. *)
  let check =
    let collected =
      List.fold_left
        (fun term spec -> Term.(const (fun xs x -> xs @ [ x ]) $ term $ option_term spec))
        (Term.const []) shared_options
    in
    let target = Arg.(required & pos 0 (some string) None & info [] ~docv:"NAME|DIR") in
    let run target opts () =
      let options = List.filter_map Fun.id opts in
      let text key =
        match List.assoc_opt key options with Some (`String v) -> Some v | _ -> None
      in
      let installed = not (String.contains target '/') in
      match
        if installed then Leash.Playbook.show ~caps target
        else Leash.Playbook.load ~caps target
      with
      | Error message -> invalid_playbook ~caps message
      | Ok book -> (
          let local = match Leash.Playbook.inspect book with `Assoc f -> f | _ -> [] in
          let print syntax =
            Cap_stdlib.print_endline ~caps
              (Yojson.Safe.pretty_to_string (`Assoc (local @ [ ("syntax", syntax) ])))
          in
          if not installed then (
            print
              (str
                 "skipped: only an installed playbook (its name, not a path) is compiled");
            0)
          else if book.Leash.Playbook.scripts = [] then (
            print (`List []);
            0)
          else
            let request =
              P.encode_request P.{ command = Playbook_check { playbook = target } }
            in
            match
              exchange ~caps ~send ~base ~config:(text "config") ~socket:(text "socket")
                request
            with
            | Error status -> status
            | Ok (P.Failure error) -> emit_error ~caps error
            | Ok (P.Success result) ->
                let scripts =
                  match field "scripts" result with `List xs -> xs | _ -> []
                in
                if List.for_all (fun s -> field "ok" s = `Bool true) scripts then (
                  print (`List scripts);
                  0)
                else
                  report ~caps
                    ~detail:(obj [ ("scripts", `List scripts) ])
                    "script-invalid" "one or more playbook scripts did not compile")
    in
    Cmd.v
      (Cli_help.command_info ~docs:"VALIDATION" "check"
         ~doc:"Check local playbook data and, for an installed NAME, compile its scripts."
         ~examples:
           [
             "leash playbook check books.toscrape.com";
             "leash playbook check ./my-playbook";
           ])
      Term.(
        const (fun target opts () -> owned (fun () -> run target opts ()))
        $ target $ collected)
  in
  (* extr-mp5z: runs one script of an installed playbook on a tab's page; the service
     looks the script up by name, and nothing of it travels on the wire. *)
  let test =
    command ~caps ~send ~base ~run_owned ~wire:"playbook_test" ~docs:"VALIDATION" "test"
      "Run one playbook script on a tab and print its validated output."
      [ pos "script" "PLAYBOOK/SCRIPT" ]
      ([
         opt "tab" Str "TAB" "The tab whose page runs the script (required).";
         opt_list "arg" Pairs "K=V" "A string argument for the script (repeatable).";
       ]
      @ shared_options)
      [
        "leash playbook test books.toscrape.com/list-books --tab t_9xk";
        "leash playbook test shop/search --tab t_9xk --arg q=gpu --arg max=2000";
      ]
  in
  (* run-m0r8: the operator's one way to merge a proposal the planner wrote. The run
     writes proposals to XDG state and never touches a playbook; this command is the hand
     that accepts one, and it validates the merged playbook before it writes. *)
  let accept =
    Cmd.v
      (Cli_help.local_info ~docs:"AUTHORING" "accept"
         ~doc:"Merge a proposed procedure into its site's playbook."
         ~examples:[ "leash playbook accept ~/.local/state/leash/proposed/shop.json" ])
      Term.(
        const (fun file () () ->
            owned (fun () ->
                match Leash.Playbook.accept ~caps file with
                | Error message -> invalid_playbook ~caps message
                | Ok accepted ->
                    Cap_stdlib.print_endline ~caps
                      (Yojson.Safe.pretty_to_string
                         (Leash.Playbook.yojson_of_accepted accepted));
                    0))
        $ file $ const ())
  in
  Cmd.group
    (Cli_help.command_info "playbook" ~doc:"Inspect, validate and grow site playbooks."
       ~man:
         [
           `S "DESCRIPTION";
           `Pre
             "A playbook is a directory that describes one site: pages, procedures, and \
              scripts.\n\
              The operator writes it. A model never does. The pilot can select it when a mission \
              fits.\n\
              Format, example, and every loader refusal: leash help playbooks";
         ]
       ~examples:[ "leash playbook list"; "leash playbook check ./my-playbook" ])
    [ list; show; check; test; accept ]

(* field-swvb: the same filters as snap, applied to the snapshot taken after the action. *)
let snap_opts =
  [
    opt "snap" Bool "" "After settling, include a fresh snapshot in the reply.";
    opt "match" Str "TEXT"
      "With --snap, keep rows whose role, name or value contains TEXT.";
    opt "limit" Int "N" "With --snap, at most N rows, default 120, max 1000.";
  ]

(* trace-o6ld: these commands read local state and never exchange a service request. *)
let traces_command ~caps ~run_owned =
  let owned run = run_owned (fun _sw -> protect ~caps run) in
  let failure why =
    Cap_stdlib.prerr_endline ~caps ("trace error: " ^ why);
    65
  in
  let store config =
    Result.map
      (fun (config : Leash.Config.t) ->
        Leash.Traces.create ~caps ~retention:config.traces.retention ())
      (load_config ~caps ~config)
  in
  let config =
    Arg.(
      value
      & opt (some string) None
      & info [ "config" ] ~docv:"FILE"
          ~doc:
            "Read retention from FILE instead of the default configuration; no service \
             is contacted.")
  in
  let site =
    Arg.(
      value
      & opt (some string) None
      & info [ "site" ] ~docv:"SITE"
          ~doc:"Select one registrable site directory, for example toscrape.com.")
  in
  let outcome =
    Arg.(
      value
      & opt (some string) None
      & info [ "outcome" ] ~docv:"OUTCOME"
          ~doc:"Keep only this outcome, for example done, blocked, or failed.")
  in
  let dry_run =
    Arg.(
      value & flag
      & info [ "dry-run" ]
          ~doc:"Print paths retention would delete without changing files.")
  in
  let list =
    Cmd.v
      (Cli_help.local_info ~docs:"TRACES" "list"
         ~doc:"List saved drive traces as TSV; no service, browser, or model is needed."
         ~examples:
           [ "leash traces list"; "leash traces list --site toscrape.com --outcome done" ])
      Term.(
        const (fun config site outcome () ->
            owned (fun () ->
                match store config with
                | Error why -> failure why
                | Ok store -> (
                    match Leash.Traces.list store ?site ?outcome () with
                    | Error why -> failure why
                    | Ok rows ->
                        let cell text =
                          String.map (function '\t' | '\n' | '\r' -> ' ' | c -> c) text
                        in
                        List.iter
                          (fun (_, (trace : Leash.Protocol.drive_trace)) ->
                            Cap_stdlib.printf ~caps "%s\t%s\t%s\t%s\t%d\t%s\n" trace.time
                              trace.site trace.outcome
                              (match trace.cost with
                              | None -> ""
                              | Some cost -> Printf.sprintf "%g" cost)
                              (List.length trace.steps) (cell trace.mission))
                          rows;
                        0)))
        $ config $ site $ outcome)
  in
  let file =
    Arg.(
      required
      & pos 0 (some string) None
      & info [] ~docv:"FILE"
          ~doc:
            "Regular saved trace file to print as JSON; symlinks and files over 8 MiB \
             are refused.")
  in
  let show =
    Cmd.v
      (Cli_help.local_info ~docs:"TRACES" "show"
         ~doc:"Print a saved trace as JSON without contacting the service."
         ~examples:
           [ "leash traces show ~/.local/state/leash/traces/toscrape.com/TRACE.json" ])
      Term.(
        const (fun file () ->
            owned (fun () ->
                match Leash.Traces.read ~caps file with
                | Error why -> failure why
                | Ok trace ->
                    Cap_stdlib.print_endline ~caps
                      (Yojson.Safe.pretty_to_string
                         (Leash.Protocol.yojson_of_drive_trace trace));
                    0))
        $ file)
  in
  let prune =
    Cmd.v
      (Cli_help.local_info ~docs:"TRACES" "prune"
         ~doc:
           "Apply local retention and print deleted paths."
         ~examples:
           [ "leash traces prune --dry-run"; "leash traces prune --site toscrape.com" ])
      Term.(
        const (fun config site dry_run () ->
            owned (fun () ->
                match store config with
                | Error why -> failure why
                | Ok store -> (
                    match
                      Leash.Traces.prune store ?site ~dry_run
                        ~now:(Leash.Traces.now store) ()
                    with
                    | Error why -> failure why
                    | Ok paths ->
                        List.iter (Cap_stdlib.print_endline ~caps) paths;
                        0)))
        $ config $ site $ dry_run)
  in
  Cmd.group
    (Cli_help.local_info ~docs:"TRACES" "traces"
       ~doc:"Inspect and prune durable local drive traces offline."
       ~examples:[ "leash traces list"; "leash traces prune --dry-run" ])
    [ list; show; prune ]

let commands ~caps ~send ~base ~run_owned =
  List.map
    (fun (name, doc, positionals, options, examples) ->
      command ~caps ~send ~base ~run_owned name doc positionals (options @ shared_options)
        examples)
    [
      ( "new",
        "Open an agent tab. agent tabs close after 30 idle minutes; human tabs are never \
         closed unless an agent takes one",
        [ pos_opt "url" "URL" ],
        [ opt "label" Str "TEXT" "Free label shown by list. It is not a capability." ],
        [
          "leash new https://example.com";
          "leash new https://example.com --label research";
        ] );
      ( "downloads",
        "List downloads started by this tab.",
        [ pos "tab" "TAB" ],
        [],
        [ "leash downloads t_9xk" ] );
      ( "list",
        "List all tabs without handles; agent tabs close after 30 idle minutes; human \
         tabs are never closed unless an agent takes one. Each tab includes page_kind \
         {name, source: declared|inferred}.",
        [],
        [ table_opt ],
        [ "leash list"; "leash list --table" ] );
      ( "take",
        "Take exactly one human tab matching one selector and return its handle. Take \
         only a tab the human told you to take; Leash does not ask or notify them. From \
         then on it is an agent tab: it closes after 30 idle minutes like any other.",
        [],
        [
          opt "url" Str "PREFIX" "Case-insensitive URL prefix.";
          opt "title" Str "TEXT" "Case-insensitive title substring.";
          opt "label" Str "TEXT" "Case-insensitive exact label.";
        ],
        [ "leash take --url https://example.com/"; "leash take --title Login" ] );
      ( "close",
        "Close a tab using its handle.",
        [ pos "tab" "TAB" ],
        [],
        [ "leash close t_9xk" ] );
      ( "status",
        "Report version, Chrome, the model key and the installed skill.",
        [],
        [],
        [ "leash status" ] );
      ( "snap",
        "Observe an indexed snapshot of a tab. The reply includes page_kind {name, \
         source: declared|inferred}.",
        [ pos "tab" "TAB" ],
        [
          opt "match" Str "TEXT" "Keep rows whose role, name or value contains TEXT.";
          opt "limit" Int "N" "At most N rows, default 120, max 1000.";
          opt "offset" Int "N"
            "Skip the first N rows, default 0. A negative offset is refused.";
          table_opt;
        ],
        [ "leash snap t_9xk --match Save --limit 10" ] );
      ( "text",
        "Extract the page's visible text.",
        [ pos "tab" "TAB" ],
        [
          opt "index" Int "N" "Read only the row at index N.";
          opt "max_chars" Int "N" "At most N characters (default and maximum 65536).";
        ],
        [ "leash text t_9xk --max-chars 300" ] );
      ( "shot",
        "Write a screenshot as a PNG to PATH.",
        [ pos "tab" "TAB"; pos "path" "PATH" ],
        [ opt "full_page" Bool "" "Capture the whole page, not the viewport." ],
        [ "leash shot t_9xk /tmp/page.png" ] );
      ( "debug",
        "Show the console, exception and failed-request ring.",
        [ pos "tab" "TAB" ],
        [
          opt "limit" Int "N" "At most N entries, default and maximum 200.";
          opt "clear" Bool "" "Discard the ring after reading it.";
        ],
        [ "leash debug t_9xk --limit 10" ] );
      ( "eval",
        "Evaluate EXPRESSION as a function body in the page; a returned promise is \
         awaited. Use return (async () => { ... })() for await, not top-level await.",
        [ pos "tab" "TAB"; pos "expression" "EXPRESSION" ],
        [
          opt "argument" Json "JSON" "JSON value bound to argument in the expression.";
          opt "index" Int "N"
            "Call the expression as (argument, element), element being the row at index \
             N.";
          opt "snapshot" Str "SNAPSHOT" "The snapshot --index names (required with it).";
        ],
        [
          "leash eval t_9xk 'return document.title'";
          "leash eval t_9xk 'return element.getBoundingClientRect().width' --snapshot \
           s_3 --index 7";
        ] );
      ( "nav",
        "Navigate a tab to a URL (http, https or about:blank).",
        [ pos "tab" "TAB"; pos "url" "URL" ],
        [],
        [ "leash nav t_9xk https://example.com" ] );
      ( "click",
        "Click the row at INDEX of SNAPSHOT. A covering label of that control is clicked \
         and reported as via label.",
        [ pos "tab" "TAB"; pos "snapshot" "SNAPSHOT"; pos "index" "INDEX" ],
        snap_opts,
        [ "leash click t_9xk s_3 7"; "leash click t_9xk s_3 7 --snap --limit 20" ] );
      ( "fill",
        "Fill the row at INDEX of SNAPSHOT with TEXT, or with --argument-file or --stdin.",
        [
          pos "tab" "TAB";
          pos "snapshot" "SNAPSHOT";
          pos "index" "INDEX";
          pos_opt "text" "TEXT";
        ],
        [
          opt "argument_file" Str "PATH"
            "Read TEXT from PATH instead of the argument (at most 64 KiB).";
          opt "stdin" Bool ""
            "Read TEXT from stdin instead of the argument (at most 64 KiB).";
        ]
        @ snap_opts,
        [
          "leash fill t_9xk s_3 1 'Ada Lovelace'";
          "leash fill t_9xk s_3 4 --stdin";
          "leash fill t_9xk s_3 4 --argument-file /tmp/secret.txt";
        ] );
      ( "press",
        "Press KEY; with --index the row is focused first. Accepted names: Enter, \
         Escape, Esc, Tab, Backspace, Delete, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, \
         Home, End, PageUp, PageDown, Space, lowercase a-z, digits 0-9, and single \
         punctuation characters - = [ ] ; , . / '.",
        [ pos "tab" "TAB"; pos "snapshot" "SNAPSHOT"; pos "key" "KEY" ],
        opt "index" Int "N" "Focus the row at index N before the key." :: snap_opts,
        [ "leash press t_9xk s_3 Enter"; "leash press t_9xk s_3 Enter --snap" ] );
      ( "select",
        "Choose OPTION, the row's observed option index.",
        [
          pos "tab" "TAB";
          pos "snapshot" "SNAPSHOT";
          pos "index" "INDEX";
          pos "option" "OPTION";
        ],
        snap_opts,
        [ "leash select t_9xk s_3 2 0 --snap" ] );
      ( "scroll",
        "Scroll the page, or the row --index names, one viewport.",
        [ pos "tab" "TAB"; pos "direction" "UP|DOWN" ],
        [ opt "index" Int "N" "Scroll the row at index N into view." ],
        [ "leash scroll t_9xk down" ] );
      ( "wait",
        "Wait for the ANDed page conditions.",
        [ pos "tab" "TAB" ],
        [
          opt "until" Json "JSON" "JSON object of the conditions below.";
          opt "url_prefix" Str "PREFIX" "Until the url starts with PREFIX.";
          opt "text" Str "TEXT" "Until the page text contains TEXT.";
          opt "index_gone" Int "N" "Until row N is gone.";
          opt "dialog" Bool "" "Until a dialog is open.";
          opt "changed_since" Str "SNAPSHOT"
            "Until the page's loader or mutation counter differs from SNAPSHOT's.";
          opt "timeout" Int "MS" "Alias of --timeout-ms.";
          opt "timeout_ms" Int "MS"
            "Bound the wait in milliseconds (default 30000, max 3600000: one hour).";
        ],
        [
          "leash wait t_9xk --text Done --timeout-ms 5000";
          "leash wait t_9xk --changed-since s_3 --timeout-ms 600000";
        ] );
      ( "upload",
        "Set PATH... on the file input at INDEX of SNAPSHOT. At most 10 files, 10 GiB \
         together.",
        [
          pos "tab" "TAB";
          pos "snapshot" "SNAPSHOT";
          pos "index" "INDEX";
          pos_many "paths" "PATH";
        ],
        [],
        [ "leash upload t_9xk s_3 12 /tmp/report.pdf" ] );
      ( "hover",
        "Move the mouse to the row at INDEX of SNAPSHOT.",
        [ pos "tab" "TAB"; pos "snapshot" "SNAPSHOT"; pos "index" "INDEX" ],
        snap_opts,
        [ "leash hover t_9xk s_3 4 --snap" ] );
      ( "check",
        "Check the control at INDEX and verify it became checked.",
        [ pos "tab" "TAB"; pos "snapshot" "SNAPSHOT"; pos "index" "INDEX" ],
        snap_opts,
        [ "leash check t_9xk s_3 8" ] );
      ( "uncheck",
        "Uncheck the control at INDEX and verify it became unchecked.",
        [ pos "tab" "TAB"; pos "snapshot" "SNAPSHOT"; pos "index" "INDEX" ],
        snap_opts,
        [ "leash uncheck t_9xk s_3 8" ] );
      ( "net",
        "List the tab's recent requests; `net TAB body ID` and `net TAB request ID` read \
         one.",
        [ pos "tab" "TAB"; pos_opt "part" "body|request"; pos_opt "id" "ID" ],
        [
          opt "match" Str "TEXT" "Keep requests whose URL contains TEXT.";
          opt "limit" Int "N" "The most recent N requests (default 100, at most 500).";
          opt "type" Str "TYPE"
            "Keep one resource type: xhr, fetch, document, script, ...";
        ],
        [
          "leash net t_9xk --type fetch --match /api/";
          "leash net t_9xk body 1000.5";
          "leash net t_9xk request 1000.5";
        ] );
      ( "cookies",
        "Read the cookies of the tab's URL, httpOnly included (read-only).",
        [ pos "tab" "TAB" ],
        [],
        [ "leash cookies t_9xk" ] );
      ( "storage",
        "Read the tab's local or session storage (read-only).",
        [ pos "tab" "TAB"; pos "area" "local|session" ],
        [],
        [ "leash storage t_9xk local" ] );
      ( "dialog",
        "Answer the page's dialog (never automatic).",
        [ pos "tab" "TAB"; pos "answer" "ACCEPT|DISMISS" ],
        [ opt "text" Str "TEXT" "Answer text for a prompt." ],
        [ "leash dialog t_9xk accept" ] );
      ( "handoff",
        "Hand the tab to the human and block until resume or timeout. The human gets a \
         notification that stays until they click Done; run this as a background job and \
         keep working. Actions on the tab answer with-human until then.",
        [ pos "tab" "TAB"; pos "reason" "REASON" ],
        [
          opt "timeout_s" Int "S"
            "Seconds before the handoff ends; default handoff.timeout_s (300). Zero or \
             negative uses config.";
        ],
        [ "leash handoff t_9xk 'The captcha needs you'" ] );
      ( "resume",
        "Resume a tab a handoff is waiting on.",
        [ pos "tab" "TAB" ],
        [],
        [ "leash resume t_9xk" ] );
    ]
  @ [
      command ~caps ~send ~base ~run_owned
        ~man:
          [
            `S "DESCRIPTION";
            `Pre
              "Drive runs one mission on one tab until done, blocked, a cap, a deadline, \
               or an error.\n\
               It may follow an installed playbook or act on the page. Leash never \
               asserts the goal.\n\
               Lanes, options, and how to read a trace: leash help drive";
            `S "ROUTING";
            `P "The pilot owns the mission. Each navigation leg has at most 15 steps.";
            `P
              "The pilot receives the mission, bounded page text and rows, prior legs, \
               and learning candidates. A leg is one navigation goal in JEV's language. \
               Leg DONE/BLOCKED returns to the pilot; only pilot done completes.";
            `P
              "--out JSONL is tagged. script-record, source playbook, is a validated \
               script record. operator-state, source operator, is one terminal bounded \
               page observation, not a record list. The Travel example writes \
               operator-state. output_kinds names the kinds in the reply. A successful \
               reply is not proof the mission succeeded. model_cost is null when any \
               call is unpriced; data.reported_cost is the known subtotal.";
          ]
        "drive"
        "Drive MISSION with the pilot, using short navigation legs and direct row actions."
        [ pos "mission" "MISSION" ]
        ([
           opt_list "secret" Strings "NAME=@FILE|NAME=-"
             "Read a secret from a file or stdin. Only its name reaches the pilot.";
           opt "tab" Str "TAB"
             "Reuse TAB instead of opening one. Does not replace a populated page.";
           opt "url" Str "URL"
             "Explicit http(s) start (start_url). Not a model navigation target.";
           opt "max_steps" Int "N"
             "Navigation-leg cap (default and maximum 15). Must be positive.";
           opt "max_procedures" Int "N"
             "Playbook-lane procedure cap (default 40), not the operator action cap.";
           opt "out" Str "FILE"
             "Append tagged JSONL: script-record from a playbook, operator-state from \
              the operator.";
           opt "deadline_s" Int "S" "Seconds for the whole mission (default pilot.deadline_s = 600).";
           opt "dry_run" Bool ""
             "Return the first pilot decision and reasoning summary without executing actions.";
           opt_list "expect" Strings "SENTENCE"
             "Mission expectation the DONE guard verifies (repeatable).";
         ]
        @ shared_options)
        [
          "leash drive 'Open Travel and return the visible titles and prices' --url \
           https://books.toscrape.com/ --out travel-state.jsonl";
          "leash drive 'Complete this page search and open the matching result' --tab \
           TAB --max-steps 15 --deadline-s 300";
          "no-playbooks: leash drive 'Open Travel and return the visible titles and \
           prices' --url https://books.toscrape.com/ --max-steps 15";
          "one-book: leash drive 'Collect the supported category' --url \
           https://books.toscrape.com/ --out books.jsonl";
          "many-books: leash drive 'Collect the supported category' --tab TAB \
           --max-steps 15";
          "none-matching: leash drive 'Search one-way and stop at the visible options' \
           --url https://www.google.com/travel/flights --max-steps 15 --deadline-s 300";
        ];
      playbook_command ~caps ~send ~base ~run_owned;
      traces_command ~caps ~run_owned;
    ]

let ( let* ) = Result.bind

let program env (config : Leash.Config.t) sw =
  let base = env.Ox_app.Env.base in
  (* Test-only: the live-acceptance gate shortens the sweep period through
     LEASH_SWEEP_INTERVAL_S so stage 1 then stage 2 are observable on a real clock in
     seconds; production always uses the 30 s contract default. A bad value fails fast,
     before Chrome launches, rather than silently changing the cadence. *)
  let* sweep_interval =
    match Cap_sys.getenv_opt ~caps:env.Ox_app.Env.caps "LEASH_SWEEP_INTERVAL_S" with
    | None | Some "" -> Ok None
    | Some text -> (
        match int_of_string_opt (String.trim text) with
        | Some n when n > 0 -> Ok (Some (Ox.Duration.seconds n))
        | Some _ | None ->
            Error (`Service "LEASH_SWEEP_INTERVAL_S must be a positive integer"))
  in
  (* svc-x8rp: the default profile is [$XDG_DATA_HOME/leash/profile], which a first run
     has not created; the service scope makes it 0700 before Chrome starts, the way the listener
     makes its own runtime directory. The validator accepted what it can create. *)
  let* () =
    match
      Leash.Config.ensure_dir ~caps:env.caps
        (Leash.Config.Text.to_string config.chrome.profile_dir)
    with
    | Ok () -> Ok ()
    | Error message ->
        Error (`Service ("cannot create the profile directory: " ^ message))
  in
  let chrome =
    Leash.Chrome.create ~sw
      (Leash.Config.chrome_config config.chrome)
      {
        Leash.Chrome.clock = base#clock;
        mgr = base#process_mgr;
        logger = env.logger;
        (* ^ncaps-4tjy: the powerbox narrowed by ascription to what Chrome may touch. *)
        caps = (env.caps :> Leash.Chrome.caps);
      }
  in
  (* own-vhqo: the two expiry durations are config. The registry counts every tab down
     to them and the sweep applies them. *)
  let seconds duration = Ox.Duration.seconds (Leash.Config.Seconds.to_int duration) in
  let idle = seconds config.expiry.idle_s in
  (* hand-04rb hand-phof hand-rg9h: the two human-facing commands a handoff runs go through
     Ox's child process, and the registry turns whatever they report into warnings. *)
  let desktop =
    Leash.Desktop.create
      ~caps:(env.caps :> Leash.Desktop.caps)
      ~clock:base#clock ~mgr:base#process_mgr
      {
        Leash.Desktop.focus_command = config.handoff.focus_command;
        notify_command = config.handoff.notify_command;
      }
  in
  let download_dir =
    Filename.concat (Leash.Config.Text.to_string config.chrome.profile_dir) "downloads"
  in
  let* () =
    match Leash.Config.ensure_dir ~caps:env.caps download_dir with
    | Ok () -> Ok ()
    | Error message -> Error (`Service ("cannot create downloads directory: " ^ message))
  in
  let tabs =
    Leash.Tabs.create ~sw ~download_dir
      ~notify:
        (Leash.Desktop.notifier
           ~caps:(env.caps :> Leash.Desktop.caps)
           ~clock:base#clock ~mgr:base#process_mgr ~command:config.notify.command)
      ~handoff_timeout_s:config.handoff.timeout_s
      ~challenge_attempt:config.challenges.attempt
      ~challenge_turns:config.challenges.turns
      ~cap:(Leash.Config.Tab_cap.to_int config.tabs.cap)
      ~tombstone_s:(Leash.Config.Seconds.to_int config.expiry.tombstone_s)
      ~idle
      {
        Leash.Tabs.chrome;
        clock = base#clock;
        logger = env.logger;
        desktop;
        caps = (env.caps :> Leash.Tabs.caps);
      }
  in
  (* own-uo77 own-hslp: the sweep is one more service in the service scope, closed with the
     switch. *)
  let _expiry =
    Leash.Expiry.create ~sw ?interval:sweep_interval ~idle ~clock:base#clock
      ~logger:env.logger tabs
  in
  (* drive-e7oi drive-yqxg: the models service is one more resource in the service scope,
     created before the listener that hands its Decide to every drive. Without a key it
     still exists — status reports that — and a drive refuses at its first Decide. *)
  let models =
    Leash.Models.create ~sw ~net:base#net ~clock:base#clock ~logger:env.logger
      config.models
  in
  let learning =
    Leash.Learning.create ~sw ~caps:env.caps ~config:config.learning
      ~warn:(fun why -> Ox_observability.Logger.warn env.logger ("learning: " ^ why))
      ()
  in
  Eio.Switch.on_release sw (fun () -> Leash.Tabs.stop tabs);
  let status_query = Ox_app.status_query [ (fun () -> Leash.Tabs.status tabs) ] in
  (* svc-o4wt: the listener owns the configured socket path; validation refused anything
     that is not a real absolute path, so the variable is resolved by now. *)
  let socket = Leash.Config.Text.to_string config.control.socket in
  let* _control =
    Leash.Control.create ~learning ~pilot:config.pilot
      ~chrome_pid:(fun () -> (Leash.Chrome.status chrome).pid)
      ~models
      ~model:(Leash.Config.Text.to_string config.models.jev_model)
        (* run-7blx: the run's three upper levels over the same one models service — the
           playbook question, the procedure question and the judgment score — and L31's
           planner stub inside them. *)
      ~levels:(Leash.Models.levels models)
      ~decide:(fun ~deadline request -> Leash.Models.decide ~deadline models request)
        (* drive-ls3c: the helper is a thunk, not a value — each drive takes its own
         instance, and with it the one-entry memo the stale-row reuse rule needs. *)
      ~text_helper:(fun () -> Leash.Models.text_helper models)
      ?traces:
        (if config.Leash.Config.traces.enabled then
           Some (Leash.Traces.create ~caps:env.caps ~retention:config.traces.retention ())
         else None)
      ~sw ~path:socket
      {
        Leash.Control.tabs;
        status_query;
        models_status = (fun () -> Leash.Models.status models);
        fs = base#fs;
        net = base#net;
        clock = base#clock;
        logger = env.logger;
        caps = (env.caps :> Leash.Control.caps);
      }
    |> Result.map_error (fun _ -> `Service "control socket acquisition failed")
  in
  Ox_app.serve ~sw ()

(* svc-x8rp: `leash config init` writes the commented default file. It is a Door subcommand
   of `config` (napp-wf22), not an ordinary command: it needs no service and sends no
   request, only the path the Door reads — which is exactly the file it writes — so
   --config and its XDG resolution stay the Door's. *)
let init_command ~caps =
  let config_file =
    Arg.(
      value
      & opt (some string) None
      & info [ "config" ] ~docv:"FILE" ~doc:"TOML configuration file to write.")
  in
  let force = Arg.(value & flag & info [ "force" ] ~doc:"Overwrite an existing file.") in
  let run config_file force () =
    let path =
      Ox_app.Config.path ~name:"leash" ~config:config_file
        ~getenv:(Cap_sys.getenv_opt ~caps)
    in
    match Leash.Config.init ~caps ~force ~path () with
    | Ok path ->
        Cap_stdlib.print_endline ~caps path;
        0
    | Error (`Exists path) ->
        usage ~caps (path ^ " already exists; pass --force to overwrite it")
    | Error (`Write error) when error.permission ->
        report ~caps
          ~detail:(obj [ ("path", str error.path) ])
          "permission-denied"
          ("cannot write configuration to " ^ error.path)
    | Error (`Write _) ->
        failure ~caps
          ("cannot write configuration to " ^ path
         ^ "; check its parent directory and permissions")
  in
  Cmd.v
    (Cli_help.local_info "init" ~doc:"Write a commented default configuration file."
       ~examples:[ "leash config init"; "leash config init --config /tmp/leash.toml" ])
    Term.(
      const (fun config_file force () ->
          protect ~caps (fun () -> run config_file force ()))
      $ config_file $ force)

let telemetry ~sw env config =
  match config.Leash.Config.otlp.endpoint with
  | None -> { Ox_app.reporters = []; span_ids = None }
  | Some endpoint ->
      Leash.Telemetry.create ~caps:env.Ox_app.Env.caps ~sw ~net:env.Ox_app.Env.base#net
        ~clock:env.Ox_app.Env.base#clock
        ~endpoint:(Leash.Config.Text.to_string endpoint)
        ~headers:
          (List.map
             (fun (header : Leash.Config.otlp_header) ->
               ( Leash.Config.Text.to_string header.name,
                 Leash.Config.Redact.expose header.value ))
             config.otlp.headers)

(* daily-azxe: the Door owns parsing, config and defects; it classifies each complete
   diagnostic before this formatter produces one JSON record. Never expose Cause.pp. *)
let problem_json (problem : Ox_app.validation_error) =
  obj [ ("pointer", str problem.pointer); ("message", str problem.message) ]

let decode_config env json =
  match
    Leash.Config.decode_all
      ~getenv:(Cap_sys.getenv_opt ~caps:env.Ox_app.Env.caps)
      ~fs:env.Ox_app.Env.base#fs json
  with
  | Ok config -> Ok config
  | Error problems ->
      Error (Yojson.Safe.to_string (`List (List.map problem_json problems)))

let diagnostic ~config_path ~kind ~message =
  let message = String.trim message in
  let record =
    match kind with
    | `Usage ->
        make_error
          ~detail:(obj [ ("diagnostic", str message) ])
          "cli-parse" "invalid command line; the command did not run"
    | `Defect ->
        make_error "internal"
          "the command failed unexpectedly; no successful result was produced"
    | `Config | `Validation -> (
        match
          try P.error_of_yojson (Yojson.Safe.from_string message)
          with _ -> Error "not an error record"
        with
        | Ok error -> error
        | Error _ ->
            let location =
              match config_path with None -> [] | Some path -> [ ("config", str path) ]
            in
            let problems =
              match try Some (Yojson.Safe.from_string message) with _ -> None with
              | Some (`List problems) -> [ ("problems", `List problems) ]
              | _ -> []
            in
            let message =
              if problems = [] then message
              else "invalid configuration; fix the reported problems"
            in
            let message =
              match config_path with
              | None -> message
              | Some path -> path ^ ": " ^ message
            in
            make_error ~detail:(obj (location @ problems)) "config-invalid" message)
  in
  Yojson.Safe.to_string (P.yojson_of_error record) ^ "\n"

(* daily-yd8s daily-ulmi: local bundle operations do not require the browser service. *)
let skill_command ~caps ~run_owned =
  let owned run = run_owned (fun _sw -> protect ~caps run) in
  let path =
    Arg.(
      value
      & pos 0 (some string) None
      & info [] ~docv:"PATH" ~doc:"Skills root; installs PATH/leash/.")
  in
  let force =
    Arg.(
      value & flag
      & info [ "f"; "force" ]
          ~doc:"Authorize automatic installation or replacement without confirmation.")
  in
  let no_input =
    Arg.(
      value & flag
      & info [ "no-input" ]
          ~doc:"Never prompt; refuse any consent-required write without --force.")
  in
  let dry_run =
    Arg.(
      value & flag
      & info [ "n"; "dry-run" ]
          ~doc:"Print planned actions without creating directories, writing or prompting.")
  in
  let confirm action path =
    let verb =
      match action with Skill_install.Install -> "Install" | Replace -> "Replace"
    in
    Cap_stdlib.eprintf ~caps "%s Leash skill at %s? [y/N] %!" verb path;
    match
      input_line (Cap_stdlib.stdin ~caps) |> String.trim |> String.lowercase_ascii
    with
    | "y" | "yes" -> true
    | _ -> false
    | exception End_of_file -> false
  in
  let show_outcome (outcome : Skill_install.outcome) =
    let action =
      match outcome.disposition with
      | Installed -> "installed"
      | Replaced -> "replaced"
      | Current -> "current"
      | Declined -> "declined"
      | Planned_install -> "planned-install"
      | Planned_replace -> "planned-replace"
    in
    Cap_stdlib.print_endline ~caps
      (Yojson.Safe.to_string (obj [ ("action", str action); ("path", str outcome.path) ]))
  in
  let install =
    let run path force no_input dry_run config_path () =
      owned (fun () ->
          let home = Option.value ~default:"" (Cap_sys.getenv_opt ~caps "HOME") in
          match load_config ~caps ~config:config_path with
          | Error message -> report ~caps "config-invalid" message
          | Ok config -> (
              match
                Skill_install.run ~caps ~home ~roots:(configured_roots config) ~path
                  ~force ~no_input ~dry_run ~stdin_is_tty:(Unix.isatty Unix.stdin)
                  ~confirm
              with
              | Ok outcomes ->
                  List.iter show_outcome outcomes;
                  0
              | Error error ->
                  List.iter show_outcome error.completed;
                  let code =
                    if
                      List.exists
                        (fun (failure : Skill_install.failure) ->
                          failure.kind = Skill_install.Internal)
                        error.failures
                    then "internal"
                    else if
                      List.exists
                        (fun (failure : Skill_install.failure) ->
                          failure.kind = Skill_install.Permission)
                        error.failures
                    then "permission-denied"
                    else "usage"
                  in
                  let failure_json (failure : Skill_install.failure) =
                    obj
                      [
                        ( "path",
                          match failure.path with None -> `Null | Some path -> str path );
                        ("message", str failure.message);
                      ]
                  in
                  let message =
                    match error.failures with
                    | [ failure ] -> failure.message
                    | failures ->
                        Printf.sprintf "%d skill targets failed" (List.length failures)
                  in
                  report ~caps
                    ~detail:
                      (obj [ ("failures", `List (List.map failure_json error.failures)) ])
                    code message))
    in
    Cmd.v
      (Cli_help.local_info "install"
         ~doc:"Install the bundled agent skill into skills roots."
         ~examples:
           [ "leash skill install --dry-run"; "leash skill install /tmp/skills --force" ])
      Term.(
        const run $ path $ force $ no_input $ dry_run
        $ Arg.(
            value
            & opt (some string) None
            & info [ "config" ] ~docv:"FILE"
                ~doc:"Read skill.roots from this TOML configuration."))
  in
  let show =
    Cmd.v
      (Cli_help.local_info "show" ~doc:"Print the bundled, version-stamped SKILL.md."
         ~examples:[ "leash skill show" ])
      Term.(
        const (fun () ->
            owned (fun () ->
                Cap_stdlib.printf ~caps "%s" Skill_install.show;
                0)))
  in
  Cmd.group
    (Cli_help.local_info "skill" ~doc:"Show or install the bundled agent skill."
       ~docs:"SKILL"
       ~examples:[ "leash skill show"; "leash skill install --dry-run" ])
    [ install; show ]

(* hdoc-ztwo hdoc-8c12 hdoc-em5c: topics are embedded markdown. This command never
   opens the control socket. errors is rendered from Protocol.Error_code. *)
let help_topics =
  let preferred =
    [
      "handles";
      "playbooks";
      "authoring";
      "expectations";
      "drive";
      "traces";
      "scripts";
      "errors";
    ]
  in
  let present =
    Leash_cli_support.Leash_help_data.topics
    |> List.map (fun (path, _) -> Filename.chop_suffix path ".md")
    |> List.sort_uniq String.compare
  in
  List.filter (fun name -> List.mem name present) preferred
  @ List.filter (fun name -> not (List.mem name preferred)) present

let help_body name =
  if String.equal name "errors" then Leash.Protocol.Error_code.topic_markdown
  else List.assoc (name ^ ".md") Leash_cli_support.Leash_help_data.topics

(* hdoc-vqj7: the offline index says what each topic answers. *)
let help_description = function
  | "handles" -> "Setup, tab handles, sharing, expiry, and human handoff."
  | "playbooks" -> "Install, validate, and read the playbook format and example."
  | "authoring" -> "Write and test reliable procedures and goals."
  | "expectations" -> "Checker sentences and when they are evaluated."
  | "drive" -> "Mission lanes, arguments, results, and traces."
  | "scripts" -> "Script and navigate steps, arguments, and validated results."
  | "traces" ->
      "Read and prune durable drive traces without a service, model, or browser."
  | "errors" -> "Error codes, exit statuses, and recovery hints."
  | name ->
      help_body name |> String.split_on_char '\n'
      |> List.find (fun line -> String.trim line <> "")
      |> String.trim

let help_command ~caps =
  let topic =
    Arg.(
      value
      & pos 0 (some string) None
      & info [] ~docv:"TOPIC" ~doc:"Topic to print. Omit to list topics.")
  in
  let run topic () =
    match topic with
    | None ->
        List.iter
          (fun name -> Cap_stdlib.printf ~caps "%s\t%s\n" name (help_description name))
          help_topics;
        0
    | Some name when List.mem name help_topics ->
        Cap_stdlib.printf ~caps "%s"
          (Leash_cli_support.Help_render.render (help_body name));
        0
    | Some name ->
        usage ~caps
          (Printf.sprintf "unknown help topic %s; topics: %s" name
             (String.concat ", " help_topics))
  in
  Cmd.v
    (Cli_help.local_info "help"
       ~doc:"Print a help topic, or list topics. Does not contact the service."
       ~examples:[ "leash help"; "leash help playbooks"; "leash help errors" ])
    Term.(const run $ topic)

(* hdoc-fixp: one paragraph. Documentation does not probe the service. *)
let orientation env () =
  let caps = env.Ox_app.Env.caps in
  let paragraph =
    String.concat " "
      [
        "Leash is a local browser service: one managed Chrome that agents share with the \
         human, driven by the leash command.";
        "leash new returns a handle you must keep; it is the only way to act on that \
         tab, and leash list never shows one.";
        "agent tabs close after 30 idle minutes; human tabs are never closed unless an \
         agent takes one.";
        "Models are OpenRouter and need an API key, OPENROUTER_API_KEY in the service's \
         environment or models.api_key in the config; the key is the operator's, not the \
         agent's.";
        "Prefer leash drive MISSION for a goal: it learns; manual commands do not. Use \
         manual commands for inspection and for steps drive cannot do. Start with leash \
         status and leash help drive.";
      ]
  in
  Cap_stdlib.print_endline ~caps paragraph;
  0

(* ^ncaps-4tjy: only the Door mints; its owned-code runner preserves each command's
   classified exit code and owns cancellation and finalizers. *)
let () =
  let config_path = ref None in
  let read_file base path =
    config_path := Some path;
    match Ox_app.Config.read_regular ~max_bytes:1_048_576 Eio.Path.(base#fs / path) with
    | Error (`Unreadable _) ->
        Error
          (`Unreadable
             "cannot read a regular configuration file within the 1 MiB limit; check the \
              path and permissions")
    | result -> result
  in
  let diagnostic ~kind ~message = diagnostic ~config_path:!config_path ~kind ~message in
  exit
    (Ox_app.run_with_args ~name:"leash" ~service_command:"serve" ~config:Leash.Config.spec
       ~service_args:(Term.const ())
       ~bare:(`Command (fun env -> Term.const (orientation env)))
       ~doc:"A local managed Chrome for agents." ~man:Cli_help.top_man
       ~exits:Cli_help.all_exits ~usage_exit:124 ~validation_exit:65 ~defect_exit:70
       ~exit_code:(fun _ -> 70)
       ~diagnostic ~read_file ~decode_with_env:decode_config
       ~journal_level:Ox_observability.Logger.Warn
       ~commands_with_env_code:(fun env _run_owned run_owned_code ->
         let caps = env.Ox_app.Env.caps in
         let base = env.Ox_app.Env.base in
         let send path request = send ~base path request in
         commands ~caps ~send ~base ~run_owned:run_owned_code
         @ [ skill_command ~caps ~run_owned:run_owned_code; help_command ~caps ])
       ~telemetry
       ~config_commands_with_env:(fun env -> [ init_command ~caps:env.Ox_app.Env.caps ])
       ~validate:Leash.Config.validate
       ~pp_err:(fun fmt (`Service _) ->
         Format.pp_print_string fmt
           (Yojson.Safe.to_string
              (P.yojson_of_error
                 (make_error "internal"
                    "the Leash service failed to start or stopped unexpectedly"))))
       (fun env _source config () sw -> program env config sw))
