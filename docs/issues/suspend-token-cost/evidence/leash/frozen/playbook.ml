(* run-tcuz run-r1e9 run-2lei run-84ds run-zmz8: playbooks are author-owned
   JSON data, never model-addressable browser targets. *)
module Cap = Ox_caps.Cap
module Cap_stdlib = Ox_caps.Cap_stdlib
module Cap_sys = Ox_caps.Cap_sys
module Cap_unix = Ox_caps.Cap_unix

let ( let* ) = Result.bind

type page = {
  name : string;
  url_pattern : string option;
  text_marker : string option;
  repeatable : bool;
}

(* map-fmt01: JEV sees [goal]; [hint] is appended to that goal. [until] is removed. *)
type goal_step = { goal : string; hint : string option }

let removed_field name = Error ("removed field " ^ name)
let json_member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None

let page_of_yojson json =
  match json with
  | `Assoc fields -> (
      match List.find_opt (fun key -> List.mem_assoc key fields) [ "description" ] with
      | Some name -> removed_field name
      | None ->
          let ( let* ) = Result.bind in
          let* name =
            match json_member "name" json with
            | Some (`String name) -> Ok name
            | Some _ -> Error "name must be a string"
            | None -> Error "page needs a name"
          in
          let* url_pattern =
            match json_member "url_pattern" json with
            | None | Some `Null -> Ok None
            | Some (`String value) -> Ok (Some value)
            | Some _ -> Error "url_pattern must be a string"
          in
          let* text_marker =
            match json_member "text_marker" json with
            | None | Some `Null -> Ok None
            | Some (`String value) -> Ok (Some value)
            | Some _ -> Error "text_marker must be a string"
          in
          let* repeatable =
            match json_member "repeatable" json with
            | None -> Ok true
            | Some (`Bool value) -> Ok value
            | Some _ -> Error "repeatable must be a boolean"
          in
          Ok { name; url_pattern; text_marker; repeatable })
  | _ -> Error "page must be an object"

let yojson_of_page (page : page) =
  `Assoc
    (List.filter_map
       (fun (key, value) -> Option.map (fun v -> (key, v)) value)
       [
         ("name", Some (`String page.name));
         ("url_pattern", Option.map (fun s -> `String s) page.url_pattern);
         ("text_marker", Option.map (fun s -> `String s) page.text_marker);
         ("repeatable", if page.repeatable then None else Some (`Bool false));
       ])

let goal_step_of_yojson json =
  match json with
  | `Assoc fields -> (
      match List.find_opt (fun key -> List.mem_assoc key fields) [ "until" ] with
      | Some name -> removed_field name
      | None ->
          let ( let* ) = Result.bind in
          let* goal =
            match json_member "goal" json with
            | Some (`String goal) -> Ok goal
            | _ -> Error "goal must be a string"
          in
          let* hint =
            match json_member "hint" json with
            | None | Some `Null -> Ok None
            | Some (`String value) -> Ok (Some value)
            | Some _ -> Error "hint must be a string"
          in
          Ok { goal; hint })
  | _ -> Error "goal step must be an object"

let yojson_of_goal_step (step : goal_step) =
  match step.hint with
  | None -> `Assoc [ ("goal", `String step.goal) ]
  | Some hint -> `Assoc [ ("goal", `String step.goal); ("hint", `String hint) ]

type use_step = { use : string; args : Yojson.Safe.t option; optional : bool option }
[@@deriving yojson]

(* extr-8o1h: a step that runs one of the playbook's own scripts by name; [args] are
   strings with the run's placeholders substituted, like a [use] step's. *)
type script_step = { script : string; args : Yojson.Safe.t option } [@@deriving yojson]
type step = Goal of goal_step | Use of use_step | Script of script_step

let step_of_yojson = function
  | `Assoc fields as json -> (
      if List.mem_assoc "navigate" fields then removed_field "navigate"
      else
        match
          List.filter (fun key -> List.mem_assoc key fields) [ "goal"; "use"; "script" ]
        with
        | [ "goal" ] -> Result.map (fun x -> Goal x) (goal_step_of_yojson json)
        | [ "use" ] -> Result.map (fun x -> Use x) (use_step_of_yojson json)
        | [ "script" ] -> Result.map (fun x -> Script x) (script_step_of_yojson json)
        | _ -> Error "step must have exactly one of goal, use or script")
  | _ -> Error "step must be an object"

let yojson_of_step = function
  | Goal step -> yojson_of_goal_step step
  | Use step -> yojson_of_use_step step
  | Script step -> yojson_of_script_step step

type repeat_until = Expectation of string | Script_check of string

let repeat_until_of_yojson = function
  | `String sentence -> Ok (Expectation sentence)
  | `Assoc [ ("script", `String name) ] -> Ok (Script_check name)
  | _ -> Error "repeat until must be an expectation or {script: name}"

let yojson_of_repeat_until = function
  | Expectation sentence -> `String sentence
  | Script_check name -> `Assoc [ ("script", `String name) ]

type repeat = {
  next : string;
  max : int;
  until : repeat_until;
  delay_ms : int option;
  key : string;
}
[@@deriving yojson]

let arg_form =
  "declare each source as {\"from\":\"mission\"},    \
   {\"from\":\"mission\",\"optional\":true}, or {\"const\":<value>}"

let valid_slug s =
  s <> ""
  && String.for_all
       (function 'a' .. 'z' | '0' .. '9' | '-' | '_' -> true | _ -> false)
       s

type arg_source = From_mission of { optional : bool } | Const of Yojson.Safe.t
type arg_decl = { name : string; source : arg_source }
type arg_decls = arg_decl list

let arg_source_of_yojson = function
  | `Assoc fields -> (
      let from = List.assoc_opt "from" fields in
      let const = List.assoc_opt "const" fields in
      let optional = List.assoc_opt "optional" fields in
      let extra =
        List.filter
          (fun key -> not (List.mem key [ "from"; "const"; "optional" ]))
          (List.map fst fields)
      in
      if extra <> [] then
        Error ("unknown arg field " ^ String.concat ", " extra ^ "; " ^ arg_form)
      else
        match (from, const) with
        | Some _, Some _ ->
            Error ("an arg is from the mission or a const, not both; " ^ arg_form)
        | None, None -> Error ("an arg needs a source; " ^ arg_form)
        | Some (`String "mission"), None -> (
            match optional with
            | None -> Ok (From_mission { optional = false })
            | Some (`Bool optional) -> Ok (From_mission { optional })
            | Some _ -> Error "optional must be a boolean")
        | Some (`String other), None ->
            Error (Printf.sprintf "unknown arg source %S; %s" other arg_form)
        | Some _, None -> Error ("from must be \"mission\"; " ^ arg_form)
        | None, Some value ->
            if optional <> None then Error ("const does not take optional; " ^ arg_form)
            else Ok (Const value))
  | _ -> Error ("an arg source is an object; " ^ arg_form)

let yojson_of_arg_source = function
  | From_mission { optional = false } -> `Assoc [ ("from", `String "mission") ]
  | From_mission { optional = true } ->
      `Assoc [ ("from", `String "mission"); ("optional", `Bool true) ]
  | Const value -> `Assoc [ ("const", value) ]

let arg_decls_of_yojson = function
  | `List _ -> Error ("args must " ^ arg_form ^ ", not a list of names")
  | `Assoc fields ->
      let rec go seen acc = function
        | [] -> Ok (List.rev acc)
        | (name, json) :: rest -> (
            if not (valid_slug name) then
              Error ("arg " ^ name ^ " must be a lowercase slug")
            else if List.mem name seen then Error ("arg " ^ name ^ " is declared twice")
            else
              match arg_source_of_yojson json with
              | Error why -> Error ("arg " ^ name ^ ": " ^ why)
              | Ok source -> go (name :: seen) ({ name; source } :: acc) rest)
      in
      go [] [] fields
  | _ -> Error ("args must be an object; " ^ arg_form)

let yojson_of_arg_decls decls =
  `Assoc (List.map (fun decl -> (decl.name, yojson_of_arg_source decl.source)) decls)

type provenance = {
  traces : string list;
  model : string;
  time : string;
  tries : int;
  last_failure : string option;
  path : string list;
  entry_kind : string; [@json.default ""]
  exit_kind : string; [@json.default ""]
  signature : (string * Trace.trace_target option) list; [@json.default []]
  kind_mapping : (string * string) list; [@json.default []]
  repeatable : bool;
  reason : string;
  gate : string;
  repair : bool;
  model_calls : int; [@json.default 0]
  model_cost : float option; [@json.null]
}
[@@deriving yojson]

type procedure = {
  slug : string;
  description : string;
  args : arg_decls option;
  steps : step list;
  expect : string list;
  repeat : repeat option;
}

let procedure_removed = [ "provenance"; "expect_timeout_s"; "max_steps"; "deadline_s" ]

let procedure_of_yojson json =
  match json with
  | `Assoc fields -> (
      match
        List.find_opt (fun key -> List.mem key procedure_removed) (List.map fst fields)
      with
      | Some name -> removed_field name
      | None ->
          let ( let* ) = Result.bind in
          let* slug =
            match json_member "slug" json with
            | Some (`String slug) -> Ok slug
            | _ -> Error "slug must be a string"
          in
          let* description =
            match json_member "description" json with
            | Some (`String description) -> Ok description
            | _ -> Error "description must be a string"
          in
          let* args =
            match json_member "args" json with
            | None | Some `Null -> Ok None
            | Some value ->
                Result.map (fun decls -> Some decls) (arg_decls_of_yojson value)
          in
          let* steps =
            match json_member "steps" json with
            | Some (`List items) ->
                let rec go acc = function
                  | [] -> Ok (List.rev acc)
                  | item :: rest -> (
                      match step_of_yojson item with
                      | Ok step -> go (step :: acc) rest
                      | Error why -> Error why)
                in
                go [] items
            | _ -> Error "steps must be a list"
          in
          let* expect =
            match json_member "expect" json with
            | Some (`List items) ->
                let rec go acc = function
                  | [] -> Ok (List.rev acc)
                  | `String sentence :: rest -> go (sentence :: acc) rest
                  | _ -> Error "expect must be a list of sentences"
                in
                go [] items
            | _ -> Error "expect must be a list of sentences"
          in
          let* repeat =
            match json_member "repeat" json with
            | None | Some `Null -> Ok None
            | Some value ->
                Result.map (fun repeat -> Some repeat) (repeat_of_yojson value)
          in
          Ok { slug; description; args; steps; expect; repeat })
  | _ -> Error "procedure must be an object"

let yojson_of_procedure (proc : procedure) =
  let fields =
    [
      ("slug", Some (`String proc.slug));
      ("description", Some (`String proc.description));
      ("args", Option.map yojson_of_arg_decls proc.args);
      ("steps", Some (`List (List.map yojson_of_step proc.steps)));
      ("expect", Some (`List (List.map (fun s -> `String s) proc.expect)));
      ("repeat", Option.map yojson_of_repeat proc.repeat);
    ]
  in
  `Assoc
    (List.filter_map (fun (key, value) -> Option.map (fun v -> (key, v)) value) fields)

(* extr-plaz extr-zdst pbk-46fr pbk-lvy9: a script as the playbook writes it. The
   result shape is not an inline object here — that is the old form (pbk-i0zl). *)
type script_decl = {
  file : string option;
  source : string option;
  description : string;
  pages : string list option;
  args : arg_decl list;
  returns_json : Yojson.Safe.t option;
}

let returns_form =
  "a leading /** returns: ... */ block, scripts/<name>.returns.json, or \"returns\":    \
   \"<shape>\" naming a shape in shapes"

let member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None

let string_field key json =
  match member key json with
  | None -> Ok None
  | Some (`String value) -> Ok (Some value)
  | Some _ -> Error (key ^ " must be a string")

let script_decl_of_yojson = function
  | `Assoc _ as json ->
      let ( let* ) = Result.bind in
      let* file = string_field "file" json in
      let* source = string_field "source" json in
      let* description =
        match member "description" json with
        | None -> Ok ""
        | Some (`String value) -> Ok value
        | Some _ -> Error "description must be a string"
      in
      let* pages =
        match member "pages" json with
        | None -> Ok None
        | Some (`List items) ->
            let rec names acc = function
              | [] -> Ok (Some (List.rev acc))
              | `String name :: rest -> names (name :: acc) rest
              | _ -> Error "pages must be a list of page-kind names"
            in
            names [] items
        | Some _ -> Error "pages must be a list of page-kind names"
      in
      let* args =
        match member "args" json with
        | None -> Ok []
        | Some value -> arg_decls_of_yojson value
      in
      let returns_json = member "returns" json in
      let* () =
        match
          List.find_opt (fun key -> member key json <> None) [ "max_bytes"; "origin" ]
        with
        | Some name -> removed_field name
        | None -> Ok ()
      in
      Ok { file; source; description; pages; args; returns_json }
  | _ -> Error "a script declaration must be an object"

let yojson_of_script_decl (decl : script_decl) =
  let fields =
    [
      ("file", Option.map (fun s -> `String s) decl.file);
      ("source", Option.map (fun s -> `String s) decl.source);
      ("description", Some (`String decl.description));
      ( "pages",
        Option.map (fun names -> `List (List.map (fun s -> `String s) names)) decl.pages
      );
      ("args", if decl.args = [] then None else Some (yojson_of_arg_decls decl.args));
      ("returns", decl.returns_json);
    ]
  in
  `Assoc
    (List.filter_map (fun (key, value) -> Option.map (fun v -> (key, v)) value) fields)

(* The section is an object of script name to declaration; the derived list codec would
   write an array, so the two functions are the object's. *)
type scripts = (string * script_decl) list

let scripts_of_yojson = function
  | `Assoc members ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | (name, json) :: rest -> (
            match script_decl_of_yojson json with
            | Ok decl -> go ((name, decl) :: acc) rest
            | Error why -> Error (Printf.sprintf "script %s: %s" name why))
      in
      go [] members
  | _ -> Error "scripts must be an object of script name to declaration"

let yojson_of_scripts scripts =
  `Assoc (List.map (fun (name, decl) -> (name, yojson_of_script_decl decl)) scripts)

type shapes = (string * Shape.t) list

let shapes_of_yojson = function
  | `Assoc members ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | (name, json) :: rest -> (
            if not (valid_slug name) then
              Error ("shape " ^ name ^ " must be a lowercase slug")
            else
              match Shape.t_of_yojson json with
              | Ok shape -> go ((name, shape) :: acc) rest
              | Error why -> Error (Printf.sprintf "shape %s: %s" name why))
      in
      go [] members
  | _ -> Error "shapes must be an object of shape name to shape"

let yojson_of_shapes shapes =
  `Assoc (List.map (fun (name, shape) -> (name, Shape.yojson_of_t shape)) shapes)

type t = {
  site : string;
  entry : string;
  description : string;
  pages : page list;
  procedures : procedure list;
  shapes : shapes option;
  scripts : scripts option;
}
[@@deriving yojson]

type checker =
  | Page_kind of string
  | Not_page_kind of string
  | Text of string
  | Download of string option
  | No_dialog
  | Row of string * string
  | Judgment of string

(* extr-plaz extr-k40c: a script the loader has resolved. The record is private: the only
   values of this type are the ones [validate] builds from a playbook directory, and the
   only function that hands script text to the browser takes one — so nothing a model wrote
   can become a script. *)
type script = {
  name : string;
  code : string;
  returns : Shape.t;
  description : string;
  pages : string list option;
  args : arg_decl list;
}

let script_max_bytes = 8 * 1024 * 1024

type draft = {
  procedure : procedure;
  pages : page list;
  scripts : script list;
  revision : string;
}

type loaded = {
  file : string;
  dir : string option;
  playbook : t;
  checks : (string * checker list) list;
  scripts : script list;
}

(* run-m0r8: a planner-written procedure is proposed to the operator, never merged by the
   run: the proposal file names the site it belongs to and carries the procedure in the
   playbook's own schema, so the [playbook accept] command can merge it under the
   operator's hand. *)
type proposal = { site : string; procedure : procedure } [@@deriving yojson]

(* run-m0r8: what [playbook accept] did — which site, which slug, the playbook file it
   wrote and whether the slug replaced one that was already there. *)
type accepted = { site : string; slug : string; playbook : string; replaced : bool }
[@@deriving yojson]

let lower = String.lowercase_ascii
let trim = String.trim
let starts prefix s = String.starts_with ~prefix s

let contains ~needle haystack =
  let needle = lower needle and haystack = lower haystack in
  let n = String.length needle in
  let rec loop i =
    i + n <= String.length haystack && (String.sub haystack i n = needle || loop (i + 1))
  in
  loop 0

let strip_dot s =
  let s = trim s in
  if String.ends_with ~suffix:"." s then String.sub s 0 (String.length s - 1) else s

(* run-tny5 run-vbys: resolution is explicit, inspectable, and never fabricates a
   selector. An apparent page-kind typo is rejected rather than scored by JEV. *)
let resolve pages sentence =
  let s = lower (strip_dot sentence) in
  let after prefix =
    String.sub s (String.length prefix) (String.length s - String.length prefix) |> trim
  in
  if starts "the page is not " s then
    let kind = after "the page is not " in
    if List.exists (fun (p : page) -> lower p.name = kind) pages then
      Ok (Not_page_kind kind)
    else Error ("unknown page kind " ^ kind)
  else if starts "the page is " s then
    let kind = after "the page is " in
    if List.exists (fun (p : page) -> lower p.name = kind) pages then Ok (Page_kind kind)
    else Error ("unknown page kind " ^ kind)
  else if starts "the page shows " s || starts "the page contains " s then
    let word =
      if starts "the page shows " s then "the page shows " else "the page contains "
    in
    let text = after word in
    if text = "" then Ok (Judgment sentence) else Ok (Text text)
  else if s = "a file was downloaded" then Ok (Download None)
  else if s = "a pdf was downloaded" || s = "a pdf file was downloaded" then
    Ok (Download (Some "application/pdf"))
  else if s = "no dialog is open" then Ok No_dialog
  else if
    starts "a " s && contains ~needle:" named " s
    && String.ends_with ~suffix:" is present" s
  then
    let rest = after "a " in
    match String.index_opt rest ' ' with
    | Some space
      when starts "named " (String.sub rest (space + 1) (String.length rest - space - 1))
      ->
        let role = String.sub rest 0 space in
        let name =
          String.sub rest (space + 7)
            (String.length rest - space - 7 - String.length " is present")
          |> trim
        in
        if name = "" then Ok (Judgment sentence) else Ok (Row (role, name))
    | _ -> Ok (Judgment sentence)
  else Ok (Judgment sentence)

let address_changed sentence =
  let s = lower (strip_dot sentence) in
  s = "the address changed" || s = "the url changed"

let wildcard pattern value =
  let pattern = lower pattern and value = lower value in
  let pieces = String.split_on_char '*' pattern in
  match pieces with
  | [ one ] -> one = value
  | _ -> (
      let rec consume offset = function
        | [] -> true
        | [ last ] ->
            String.ends_with ~suffix:last value
            && String.length value - String.length last >= offset
        | piece :: tail ->
            let rec seek i =
              if i + String.length piece > String.length value then false
              else if String.sub value i (String.length piece) = piece then
                consume (i + String.length piece) tail
              else seek (i + 1)
            in
            seek offset
      in
      match pieces with
      | first :: tail when starts first value -> consume (String.length first) tail
      | _ -> false)

let page_kind pages ~url ~text =
  (* Inferred kinds ignore query and fragment annotations. Keep authored patterns
     that explicitly name either annotation matching against the complete URL. *)
  let base_url =
    let stop =
      List.fold_left
        (fun stop marker ->
          match String.index_opt url marker with Some at -> min stop at | None -> stop)
        (String.length url) [ '?'; '#' ]
    in
    String.sub url 0 stop
  in
  List.find_map
    (fun (page : page) ->
      if
        Option.fold ~none:false
          ~some:(fun p ->
            wildcard p
              (if String.contains p '?' || String.contains p '#' then url else base_url))
          page.url_pattern
        || Option.fold ~none:false
             ~some:(fun marker -> contains ~needle:marker text)
             page.text_marker
      then Some page.name
      else None)
    pages

let valid_name s =
  s <> ""
  && String.for_all
       (function 'a' .. 'z' | '0' .. '9' | '-' | '_' -> true | _ -> false)
       s

(* run-rq6i run-m0r8: the rules one procedure must satisfy. The loader applies them to
   every procedure of a file; L32 applies the same function to a planner's answer before
   the loop executes it and to a proposal before it is merged, because a procedure that did
   not come from a validated file can break two things a file cannot: it can call itself —
   a runaway recursion the file's cycle walk would have caught — and its expectations can
   name a page kind the playbook does not declare. [file] only names the origin in the
   message. *)
(* map-op06: share the loader's top-level/use distinction with learning. Authored
   scripts and navigations retain their existing rule; learned operations need two goals. *)
let check_goal_count ~minimum ?(file = "<procedure>") (book : t) (proc : procedure) =
  let goals =
    List.length (List.filter (function Goal _ -> true | _ -> false) proc.steps)
  in
  let sub =
    List.exists
      (fun (parent : procedure) ->
        parent.slug <> proc.slug
        && List.exists
             (function Use step -> step.use = proc.slug | _ -> false)
             parent.steps)
      book.procedures
  in
  if goals >= minimum || sub then Ok ()
  else
    Error
      (Printf.sprintf
         "%s: procedure %s needs at least %d goal steps; fewer are allowed only as a \
          use: sub-procedure"
         file proc.slug minimum)

let check_procedure ?(file = "<procedure>") (book : t) (proc : procedure) =
  let ( let* ) = Result.bind in
  let procedure = proc.slug in
  let refuse reason =
    Error (Printf.sprintf "%s: procedure %s: %s" file procedure reason)
  in
  let require condition message = if condition then Ok () else refuse message in
  let unique names =
    List.length names = List.length (List.sort_uniq String.compare names)
  in
  let slugs = List.map (fun (p : procedure) -> p.slug) book.procedures in
  let script_names = List.map fst (Option.value ~default:[] book.scripts) in
  let* () = require (valid_name procedure) "slug must be a lowercase slug" in
  let* () = require (trim proc.description <> "") "description must not be empty" in
  let* () =
    require
      (proc.expect <> [] && List.for_all (fun s -> trim s <> "") proc.expect)
      "expect must be a non-empty list of sentences"
  in
  let* () = require (proc.steps <> []) "steps must not be empty" in
  let* () =
    require
      (let names =
         List.map
           (fun (decl : arg_decl) -> decl.name)
           (Option.value ~default:[] proc.args)
       in
       unique names && List.for_all valid_name names)
      "args must be unique lowercase names"
  in
  let* () =
    match proc.repeat with
    | None -> Ok ()
    | Some repeat ->
        let* () =
          require (repeat.max > 0 && repeat.max <= 1000) "repeat max must be 1..1000"
        in
        let* () =
          require
            (repeat.next <> procedure && List.mem repeat.next slugs)
            "repeat next must name another procedure"
        in
        let next =
          List.find (fun (p : procedure) -> p.slug = repeat.next) book.procedures
        in
        let* () = require (next.repeat = None) "repeat next must not itself repeat" in
        let* () =
          match repeat.until with
          | Expectation sentence ->
              require (trim sentence <> "") "repeat until must not be empty"
          | Script_check name ->
              require
                (List.mem_assoc name (Option.value ~default:[] book.scripts))
                "repeat until script must be declared"
        in
        let* () = require (trim repeat.key <> "") "repeat key must not be empty" in
        let* () =
          require
            (Option.fold ~none:true
               ~some:(fun ms -> ms >= 0 && ms <= 60_000)
               repeat.delay_ms)
            "repeat delay_ms must be 0..60000"
        in
        let* _ =
          match repeat.until with
          | Expectation sentence -> Result.map (fun _ -> ()) (resolve book.pages sentence)
          | Script_check _ -> Ok ()
        in
        Ok ()
  in
  let rec steps = function
    | [] -> Ok ()
    | Goal goal :: tail ->
        let* () = require (trim goal.goal <> "") "goal must not be empty" in
        steps tail
    | Use use :: tail ->
        let* () =
          if use.use = procedure then
            refuse ("cycle of use: " ^ procedure ^ " -> " ^ use.use)
          else require (List.mem use.use slugs) ("use of unknown slug " ^ use.use)
        in
        let* () =
          require
            (match use.args with
            | None -> true
            | Some (`Assoc fields) ->
                List.for_all (function _, `String _ -> true | _ -> false) fields
            | Some _ -> false)
            "use args must be an object of strings"
        in
        steps tail
    | Script step :: tail ->
        let* () =
          require
            (List.mem step.script script_names)
            ("script step names unknown script " ^ step.script)
        in
        let* () =
          require
            (match step.args with
            | None -> true
            | Some (`Assoc fields) ->
                List.for_all (function _, `String _ -> true | _ -> false) fields
            | Some _ -> false)
            "script args must be an object of strings"
        in
        (* hdoc-vqj7: pinned steps bypass automatic argument filling. A declaration
           alone must not look like it supplies a required value to the script. *)
        let declarations =
          (List.assoc step.script (Option.value ~default:[] book.scripts)).args
        in
        let supplied =
          match step.args with Some (`Assoc fields) -> List.map fst fields | _ -> []
        in
        let* () =
          List.fold_left
            (fun result (decl : arg_decl) ->
              let* () = result in
              match decl.source with
              | From_mission { optional = true } -> Ok ()
              | From_mission { optional = false } | Const _ ->
                  require (List.mem decl.name supplied)
                    (Printf.sprintf
                       "script step %s must pass declared argument %s in step args; \
                        declarations do not fill pinned steps"
                       step.script decl.name))
            (Ok ()) declarations
        in
        steps tail
  in
  let* () = steps proc.steps in
  let rec expectations = function
    | [] -> Ok ()
    | sentence :: tail ->
        let* _ =
          Result.map_error
            (fun reason -> Printf.sprintf "%s: procedure %s: %s" file procedure reason)
            (resolve book.pages sentence)
        in
        expectations tail
  in
  expectations proc.expect

(* extr-plaz: a script is a file relative to its playbook directory or a short inline
   source. A file is resolved at load: no absolute path, no [..] component, and the path
   after every symlink is resolved must still be inside the directory — a link may point
   at another file of the playbook, never out of it. The text is read here, once, so a run
   works from what the operator saw at load. *)
let max_inline_bytes = 4096
let max_file_bytes = 1024 * 1024

(* ^ncaps-4tjy: a directory comes with the capability to read it; a playbook decoded
   without one (a discovery seed, a proposal) cannot name a file script. *)
let read_script_file ~dir file =
  let ( let* ) = Result.bind in
  let* caps, dir =
    match dir with
    | Some (caps, dir) -> Ok (caps, dir)
    | None -> Error "a file script needs a playbook directory"
  in
  let* () =
    if file = "" then Error "file must not be empty"
    else if String.contains file '\000' then Error "file must not contain NUL"
    else if not (Filename.is_relative file) then
      Error (Printf.sprintf "file %s must be relative to the playbook directory" file)
    else if List.mem ".." (String.split_on_char '/' file) then
      Error (Printf.sprintf "file %s must not contain .." file)
    else if not (String.ends_with ~suffix:".js" file) then
      Error (Printf.sprintf "file %s must be a .js file" file)
    else Ok ()
  in
  match (Unix.realpath dir, Unix.realpath (Filename.concat dir file)) with
  | exception Unix.Unix_error (why, _, _) ->
      Error (Printf.sprintf "file %s: %s" file (Unix.error_message why))
  | root, real -> (
      if not (starts (root ^ "/") real) then
        Error (Printf.sprintf "file %s resolves outside the playbook directory" file)
      else
        match Unix.stat real with
        | exception Unix.Unix_error (why, _, _) ->
            Error (Printf.sprintf "file %s: %s" file (Unix.error_message why))
        | { Unix.st_kind = Unix.S_REG; st_size; _ } -> (
            if st_size > max_file_bytes then
              Error (Printf.sprintf "file %s is over %d bytes" file max_file_bytes)
            else
              try Ok (Cap_stdlib.In_channel.with_open_bin ~caps real In_channel.input_all)
              with Sys_error why -> Error (Printf.sprintf "file %s: %s" file why))
        | _ -> Error (Printf.sprintf "file %s is not a regular file" file))

let script_only_message =
  "every procedure is a script; use `leash eval` or `playbook test`, or add the goal \
   steps JEV drives"

let returns_comment code =
  let trimmed = String.trim code in
  let prefix = "/** returns:" in
  if not (String.starts_with ~prefix trimmed) then Ok None
  else
    let rest =
      String.sub trimmed (String.length prefix)
        (String.length trimmed - String.length prefix)
    in
    let rec close i =
      if i + 1 >= String.length rest then None
      else if rest.[i] = '*' && rest.[i + 1] = '/' then Some i
      else close (i + 1)
    in
    match close 0 with
    | None -> Error "returns block is missing */"
    | Some i -> (
        let text = String.trim (String.sub rest 0 i) in
        try Ok (Some (Yojson.Safe.from_string text))
        with Yojson.Json_error why -> Error ("returns block: " ^ why))

let arg_idents code =
  let n = String.length code in
  let ident_start c = match c with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false in
  let ident c = ident_start c || match c with '0' .. '9' -> true | _ -> false in
  let rec loop i acc =
    if i + 5 > n then List.sort_uniq String.compare acc
    else if String.sub code i 5 = "args." then
      let start = i + 5 in
      if start < n && ident_start code.[start] then
        let rec stop j = if j < n && ident code.[j] then stop (j + 1) else j in
        let stop = stop start in
        loop stop (String.sub code start (stop - start) :: acc)
      else loop (i + 1) acc
    else loop (i + 1) acc
  in
  loop 0 []

let read_sidecar ~dir name =
  match dir with
  | None -> Ok None
  | Some (caps, root) -> (
      let relative = Filename.concat "scripts" (name ^ ".returns.json") in
      let path = Filename.concat root relative in
      if not (Sys.file_exists path) then Ok None
      else
        match (Unix.realpath root, Unix.realpath path) with
        | exception Unix.Unix_error (why, _, _) ->
            Error (Printf.sprintf "%s: %s" relative (Unix.error_message why))
        | root, real -> (
            if not (starts (root ^ "/") real) then
              Error (Printf.sprintf "%s resolves outside the playbook directory" relative)
            else
              try
                let text =
                  Cap_stdlib.In_channel.with_open_bin ~caps real In_channel.input_all
                in
                try Ok (Some (Yojson.Safe.from_string text))
                with Yojson.Json_error why -> Error (relative ^ ": " ^ why)
              with Sys_error why -> Error (Printf.sprintf "%s: %s" relative why)))

let resolve_shape ~shapes json =
  match json with
  | `String name -> (
      match List.assoc_opt name (Option.value ~default:[] shapes) with
      | Some shape -> Ok shape
      | None -> Error (Printf.sprintf "unknown shape %S" name))
  | other -> Shape.t_of_yojson other

let resolve_scripts ~file ~dir (book : t) =
  let decls = Option.value ~default:[] book.scripts in
  let refuse name why = Error (Printf.sprintf "%s: script %s: %s" file name why) in
  let page_names = List.map (fun (page : page) -> page.name) book.pages in
  let rec go seen acc = function
    | [] -> Ok (List.rev acc)
    | (name, (decl : script_decl)) :: rest -> (
        if not (valid_name name) then refuse name "name must be a lowercase slug"
        else if List.mem name seen then refuse name "declared twice"
        else
          match Ok () with
          | Error why -> refuse name why
          | Ok () -> (
              let code =
                match (decl.file, decl.source) with
                | Some path, None ->
                    Result.map (fun code -> code) (read_script_file ~dir path)
                | None, Some source ->
                    if String.length source > max_inline_bytes then
                      Error
                        (Printf.sprintf "inline source is over %d bytes: put it in a file"
                           max_inline_bytes)
                    else Ok source
                | _ -> Error "declare exactly one of file or source"
              in
              match code with
              | Error why -> refuse name why
              | Ok code -> (
                  if String.trim code = "" then refuse name "the script is empty"
                  else if String.contains code (Char.chr 0) then
                    refuse name "the script contains NUL"
                  else if
                    String.trim decl.description = ""
                    || String.contains decl.description (Char.chr 10)
                  then refuse name "description must be one sentence"
                  else
                    match decl.pages with
                    | Some pages
                      when List.exists (fun page -> not (List.mem page page_names)) pages
                      ->
                        let page =
                          List.find (fun page -> not (List.mem page page_names)) pages
                        in
                        refuse name ("pages names unknown page kind " ^ page)
                    | _ -> (
                        let declared =
                          List.map (fun (decl : arg_decl) -> decl.name) decl.args
                        in
                        match
                          List.find_opt
                            (fun ident -> not (List.mem ident declared))
                            (arg_idents code)
                        with
                        | Some ident ->
                            refuse name
                              (Printf.sprintf "args.%s is read but not declared; %s" ident
                                 arg_form)
                        | None -> (
                            match (returns_comment code, read_sidecar ~dir name) with
                            | Error why, _ | _, Error why -> refuse name why
                            | Ok comment, Ok sidecar -> (
                                let declared =
                                  match decl.returns_json with
                                  | None -> Ok []
                                  | Some (`String shape) ->
                                      Ok [ ("declaration", `String shape) ]
                                  | Some _ ->
                                      Error
                                        ("returns belongs beside the script ("
                                       ^ returns_form
                                       ^ "), not an inline shape on the declaration")
                                in
                                match declared with
                                | Error why -> refuse name why
                                | Ok declared -> (
                                    let sources =
                                      declared
                                      @ (match comment with
                                        | None -> []
                                        | Some json -> [ ("comment", json) ])
                                      @
                                      match sidecar with
                                      | None -> []
                                      | Some json -> [ ("sidecar", json) ]
                                    in
                                    match sources with
                                    | [] ->
                                        refuse name
                                          ("returns belongs beside the script ("
                                         ^ returns_form ^ ")")
                                    | _ :: _ :: _ ->
                                        refuse name
                                          ("returns is declared more than once; "
                                         ^ returns_form)
                                    | [ (_, json) ] -> (
                                        match resolve_shape ~shapes:book.shapes json with
                                        | Error why -> refuse name why
                                        | Ok returns -> (
                                            match Shape.check_returns returns with
                                            | Error why -> refuse name why
                                            | Ok () ->
                                                go (name :: seen)
                                                  ({
                                                     name;
                                                     code;
                                                     returns;
                                                     description =
                                                       String.trim decl.description;
                                                     pages = decl.pages;
                                                     args = decl.args;
                                                   }
                                                  :: acc)
                                                  rest)))))))))
  in
  go [] [] decls

(* map-op08: proposed scripts have a narrower contract than authored scripts.
   Scan source conservatively, including comments and quoted property names; reject
   escaped identifiers rather than accepting spelling tricks around the denylist. *)
let check_proposed_script code =
  let lower = String.lowercase_ascii code in
  let forbidden =
    [
      "location";
      "history";
      "submit";
      "requestsubmit";
      "click";
      "dispatchevent";
      "focus";
      "fetch";
      "xmlhttprequest";
      "websocket";
      "sendbeacon";
      "navigator";
      "localstorage";
      "sessionstorage";
      "cookie";
      "indexeddb";
      "eval";
      "constructor";
    ]
  in
  let token name = Str.regexp ("\\b" ^ name ^ "\\b") in
  let references re =
    try
      ignore (Str.search_forward re lower 0);
      true
    with Not_found -> false
  in
  let compact = Str.global_replace (Str.regexp "[ \t\r\n]+") "" lower in
  let unsafe =
    List.exists (fun name -> references (token name)) forbidden
    || (try
          ignore (Str.search_forward (token "Function") code 0);
          true
        with Not_found -> false)
    || references (Str.regexp "\\bimport[ \t\r\n]*(")
    || references (Str.regexp "\\bwindow[ \t\r\n]*\\.[ \t\r\n]*open\\b")
    || String.contains code '\\'
    || (try
          ignore (Str.search_forward (Str.regexp "\\bvalue['\"]?\\]?[=+*/-]") compact 0);
          true
        with Not_found -> false)
    ||
      try
        ignore (Str.search_forward (Str.regexp "window\\[['\"]open['\"]\\]") compact 0);
        true
      with Not_found -> false
  in
  if unsafe then
    Error
      "compiled script must be read-only: forbidden navigation, input, network, storage \
       or dynamic code reference"
  else Ok ()

let validate ~file ~dir (book : t) =
  let ( let* ) = Result.bind in
  let refuse ?(procedure = "<playbook>") reason =
    Error (Printf.sprintf "%s: procedure %s: %s" file procedure reason)
  in
  let require condition ?procedure message =
    if condition then Ok () else refuse ?procedure message
  in
  let unique names =
    List.length names = List.length (List.sort_uniq String.compare names)
  in
  let* () =
    require
      (book.site <> "" && book.site <> "." && book.site <> ".."
      && (not (String.contains book.site '/'))
      && not (String.contains book.site '\000'))
      "invalid site"
  in
  let* () =
    require
      (starts "https://" book.entry || starts "http://" book.entry)
      "entry must be an HTTP(S) URL"
  in
  let* () =
    require
      (not (String.contains book.entry '@'))
      "entry URL must not contain credentials"
  in
  let* () = require (trim book.description <> "") "description must not be empty" in
  let names = List.map (fun (p : page) -> p.name) book.pages in
  let* () =
    require
      (unique names && List.for_all valid_name names)
      "page kind names must be unique lowercase slugs"
  in
  let* () =
    let rec pages = function
      | [] -> Ok ()
      | (p : page) :: rest ->
          let* () =
            require
              (p.url_pattern <> None || p.text_marker <> None)
              ("page kind " ^ p.name ^ " needs url_pattern or text_marker")
          in
          pages rest
    in
    pages book.pages
  in
  let* () =
    require
      (List.length book.procedures <= 200)
      "more than 200 procedures (255-option JEV ceiling)"
  in
  let slugs = List.map (fun (p : procedure) -> p.slug) book.procedures in
  let* () =
    require
      (unique slugs && List.for_all valid_name slugs)
      "procedure slugs must be unique lowercase slugs"
  in
  let rec procedures = function
    | [] -> Ok ()
    | (proc : procedure) :: rest ->
        let* () = check_procedure ~file book proc in
        procedures rest
  in
  let* () = procedures book.procedures in
  let rec visit path slug =
    if List.mem slug path then
      refuse ~procedure:slug
        ("cycle of use: " ^ String.concat " -> " (List.rev (slug :: path)))
    else
      let proc = List.find (fun (p : procedure) -> p.slug = slug) book.procedures in
      let rec steps = function
        | [] -> Ok ()
        | (Goal _ | Script _) :: tail -> steps tail
        | Use use :: tail ->
            let* () = visit (slug :: path) use.use in
            steps tail
      in
      steps proc.steps
  in
  let rec cycles = function
    | [] -> Ok ()
    | (p : procedure) :: tail ->
        let* () = visit [] p.slug in
        cycles tail
  in
  let* () = cycles book.procedures in
  let checks =
    List.map
      (fun (p : procedure) ->
        ( p.slug,
          List.map
            (fun sentence ->
              match resolve book.pages sentence with Ok c -> c | Error _ -> assert false)
            p.expect ))
      book.procedures
  in
  let has_goal (proc : procedure) =
    List.exists (function Goal _ -> true | _ -> false) proc.steps
  in
  let subs =
    List.concat_map
      (fun (proc : procedure) ->
        List.filter_map (function Use step -> Some step.use | _ -> None) proc.steps)
      book.procedures
    @ List.filter_map
        (fun (proc : procedure) ->
          Option.map (fun (repeat : repeat) -> repeat.next) proc.repeat)
        book.procedures
  in
  let* () =
    if book.procedures = [] || List.exists has_goal book.procedures then
      let rec orphan = function
        | [] -> Ok ()
        | proc :: rest ->
            let* () =
              if has_goal proc || List.mem proc.slug subs then Ok ()
              else check_goal_count ~minimum:1 ~file book proc
            in
            orphan rest
      in
      orphan book.procedures
    else Error (file ^ ": " ^ script_only_message)
  in
  let* scripts = resolve_scripts ~file ~dir book in
  let* () =
    require (List.length scripts <= 246) "more than 246 scripts (255-option JEV ceiling)"
  in
  Ok { file; dir = Option.map snd dir; playbook = book; checks; scripts }

let of_json ?dir ~file json =
  match json with
  | `Assoc fields when List.mem_assoc "provenance" fields ->
      Error (file ^ ": removed field provenance")
  | `Assoc fields when List.mem_assoc "returns" fields ->
      Error
        (file ^ ": returns belongs beside the script (" ^ returns_form
       ^ "), not at the playbook top level")
  | _ -> (
      match t_of_yojson json with
      | Error reason -> Error (file ^ ": " ^ reason)
      | Ok book -> validate ~file ~dir book)

(* The playbook as another playbook value, validated in the same directory: what a merge
   or a planner's procedure needs, so a file script is resolved against the directory it
   came from. *)
let reads caps = (caps : < Cap.fs_read ; .. > :> Cap.fs_read)

let revalidate ~caps (book : loaded) playbook =
  validate ~file:book.file
    ~dir:(Option.map (fun dir -> (reads caps, dir)) book.dir)
    playbook

let provenance_filename slug = slug ^ ".provenance.json"

let is_provenance_sidecar name =
  let suffix = ".provenance.json" in
  String.ends_with ~suffix name
  &&
  let stem = String.sub name 0 (String.length name - String.length suffix) in
  valid_slug stem

(* extr-plaz: a playbook is a directory, [<name>/playbook.json] and whatever files sit
   beside it. Errors name the playbook.json path — or the path given when it is not a
   directory at all. Provenance sidecars are the only other JSON allowed (map-fmt02). *)
let load ~caps dir =
  let file = Filename.concat dir "playbook.json" in
  if Sys.file_exists dir && not (Sys.is_directory dir) then
    Error (dir ^ ": a playbook is a directory holding playbook.json, not a single file")
  else if not (Sys.file_exists file) then
    if
      Sys.file_exists (Filename.concat dir "playbook.yaml")
      || Sys.file_exists (Filename.concat dir "playbook.yml")
    then
      Error (file ^ ": playbooks use JSON (<name>/playbook.json); YAML is not supported")
    else Error (file ^ ": No such file or directory")
  else
    let extra =
      Cap_sys.readdir ~caps dir |> Array.to_list
      |> List.filter (fun name ->
          (not (String.starts_with ~prefix:"." name))
          && String.ends_with ~suffix:".json" name
          && name <> "playbook.json"
          && not (is_provenance_sidecar name))
      |> List.sort String.compare
    in
    if extra <> [] then
      Error
        (Printf.sprintf
           "%s: stray JSON beside playbook.json (%s); a playbook directory holds \
            one             playbook.json"
           dir (String.concat ", " extra))
    else
      try
        let ch = Cap_stdlib.open_in_bin ~caps file in
        Fun.protect
          ~finally:(fun () -> close_in ch)
          (fun () ->
            let json = Yojson.Safe.from_channel ch in
            of_json ~dir:(reads caps, dir) ~file json)
      with
      | Sys_error reason -> Error (file ^ ": " ^ reason)
      | Yojson.Json_error reason -> Error (file ^ ": invalid JSON: " ^ reason)

let script_named (book : loaded) name =
  List.find_opt (fun (script : script) -> script.name = name) book.scripts

let offered_scripts (book : loaded) ~url ~text =
  let kind = page_kind book.playbook.pages ~url ~text in
  List.filter
    (fun (script : script) ->
      match script.pages with
      | None -> true
      | Some pages -> (
          match kind with None -> false | Some kind -> List.mem kind pages))
    book.scripts

let directory ~caps () =
  let home =
    match Cap_sys.getenv_opt ~caps "XDG_CONFIG_HOME" with
    | Some s when s <> "" -> s
    | _ ->
        Filename.concat
          (Option.value ~default:"." (Cap_sys.getenv_opt ~caps "HOME"))
          ".config"
  in
  Filename.concat (Filename.concat home "leash") "playbooks"

let list ~caps () =
  let dir = directory ~caps () in
  if not (Sys.file_exists dir) then Ok []
  else
    try
      let files =
        Cap_sys.readdir ~caps dir |> Array.to_list |> List.sort String.compare
      in
      let rec collect acc = function
        | [] -> Ok (List.rev acc)
        | entry :: tail ->
            let path = Filename.concat dir entry in
            if String.starts_with ~prefix:"." entry then collect acc tail
            else if Sys.is_directory path then
              match load ~caps path with
              | Error _ as error -> error
              | Ok book -> collect (book :: acc) tail
            else if
              List.exists
                (fun suffix -> String.ends_with ~suffix entry)
                [ ".json"; ".yaml"; ".yml" ]
            then
              Error (path ^ ": playbooks are directories; move it to <name>/playbook.json")
            else collect acc tail
      in
      collect [] files
    with Sys_error reason -> Error (dir ^ ": " ^ reason)

let show ~caps name =
  if
    name = "" || name = "." || name = ".." || String.contains name '/'
    || String.contains name '\\' || String.contains name '\000'
    || String.contains name '*' || String.contains name '?'
  then Error (name ^ ": invalid playbook name")
  else load ~caps (Filename.concat (directory ~caps ()) name)

(* run-m0r8: the XDG state directory proposals live in, resolved the way the config
   directory is: [$XDG_STATE_HOME/leash/proposed], [$HOME/.local/state] when the variable
   is unset. The run writes here and nowhere else — the playbook an operator authored is
   never touched automatically (story 32). *)
let proposed_directory ~caps () =
  let home =
    match Cap_sys.getenv_opt ~caps "XDG_STATE_HOME" with
    | Some s when s <> "" -> s
    | _ ->
        Filename.concat
          (Option.value ~default:"." (Cap_sys.getenv_opt ~caps "HOME"))
          ".local/state"
  in
  Filename.concat (Filename.concat home "leash") "proposed"

(* run-m0r8: write one proposed procedure to
   [<state>/leash/proposed/<site>-<slug>.json], 0600 in a private directory. A run calls
   this once a planner-written procedure has run and passed its expectations; it never
   writes to the playbook directory. *)
let read_proposal ~caps path =
  try
    let channel = Cap_stdlib.open_in_bin ~caps path in
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () ->
        match proposal_of_yojson (Yojson.Safe.from_channel channel) with
        | Ok proposal -> Ok proposal
        | Error reason -> Error (path ^ ": " ^ reason))
  with
  | Sys_error reason -> Error (path ^ ": " ^ reason)
  | Yojson.Json_error reason -> Error (path ^ ": invalid JSON: " ^ reason)

(* run-m0r8: the installed playbook a proposal's site names. A site served by two files is
   refused rather than guessed: the operator resolves which file is the site's before the
   merge. *)
let installed_for_site ~caps site =
  match list ~caps () with
  | Error _ as error -> error
  | Ok books -> (
      match List.filter (fun (book : loaded) -> book.playbook.site = site) books with
      | [] -> Error (Printf.sprintf "no installed playbook for site %s" site)
      | [ book ] -> Ok book
      | books ->
          Error
            (Printf.sprintf "site %s is served by %d playbooks: %s" site
               (List.length books)
               (String.concat ", " (List.map (fun (book : loaded) -> book.file) books))))

(* run-m0r8: what the [playbook accept] command does — read the proposal, merge its
   procedure into the site's playbook by slug (replacing the same slug, appending
   otherwise), refuse the merge unless the merged playbook validates, and only then write
   it back. The proposal file is left where it is. *)
(* map-lnwr map-h5ym: preserve the old map before replacement or retirement. *)
let archive_procedure ?reason ~caps ~site (proc : procedure) =
  let directory = Filename.concat (proposed_directory ~caps ()) "retired" in
  let json = yojson_of_proposal { site; procedure = proc } in
  let json =
    match (reason, json) with
    | Some reason, `Assoc fields ->
        `Assoc (("retirement_reason", `String reason) :: fields)
    | _ -> json
  in
  let json = Yojson.Safe.pretty_to_string json ^ "\n" in
  let path =
    Filename.concat directory
      (site ^ "-" ^ proc.slug ^ "-" ^ Digest.to_hex (Digest.string json) ^ ".json")
  in
  let* () = Config.ensure_dir ~caps directory in
  try
    let ch =
      Cap_stdlib.open_out_gen ~caps
        [ Open_creat; Open_trunc; Open_wronly; Open_binary ]
        0o600 path
    in
    Fun.protect ~finally:(fun () -> close_out ch) (fun () -> output_string ch json);
    Ok ()
  with Sys_error why -> Error why

let non_repeatable_context text =
  let text = String.lowercase_ascii text in
  List.exists
    (fun word ->
      try
        ignore (Str.search_forward (Str.regexp_string word) text 0);
        true
      with Not_found -> false)
    [
      "payment";
      "pay";
      "checkout";
      "confirm";
      "upload";
      "post";
      "send";
      "delete";
      "deletion";
    ]

(* map-yzqp: the table has no form ancestry. Only an explicitly named search
   target gives enough scope to exclude other controls; generic OK/Continue,
   missing targets and free page warnings retain the conservative full context. *)
let action_risk_context ~(snapshot : Protocol.snapshot) ~text ~index =
  let target =
    Option.bind index (fun index ->
        List.find_opt (fun (row : Protocol.row) -> row.index = index) snapshot.rows)
  in
  let text =
    match target with
    | Some target
      when (not snapshot.truncated) && snapshot.offset = 0
           && snapshot.total = List.length snapshot.rows
           && snapshot.dialog = None
           && List.mem target.role [ "button"; "combobox"; "searchbox"; "textbox" ]
           &&
           let name = String.lowercase_ascii (String.trim target.name) in
           name = "search" || String.starts_with ~prefix:"search " name ->
        let ambient =
          List.filter_map
            (fun (row : Protocol.row) ->
              if
                row.index <> target.index
                && List.mem row.role
                     [
                       "button"; "link"; "menuitem"; "tab"; "checkbox"; "radio"; "switch";
                     ]
              then Some (String.trim row.name)
              else None)
            snapshot.rows
        in
        (* Each unrelated row can account for one label occurrence, not every
           identical warning in the body. Duplicate row names are ambiguous. *)
        let ambient =
          List.filter
            (fun name -> List.length (List.filter (( = ) name) ambient) = 1)
            ambient
        in
        let rec scoped labels = function
          | [] -> []
          | line :: rest ->
              let name = String.trim line in
              if List.mem name labels then scoped (List.filter (( <> ) name) labels) rest
              else line :: scoped labels rest
        in
        scoped ambient (String.split_on_char '\n' text) |> String.concat "\n"
    | _ -> text
  in
  String.concat " "
    [
      snapshot.url;
      snapshot.title;
      Option.fold ~none:""
        ~some:(fun (kind : Protocol.page_kind_label) -> kind.name)
        snapshot.page_kind;
      Option.fold ~none:"" ~some:(fun (row : Protocol.row) -> row.name) target;
      text;
    ]

let non_repeatable_action ~context operation =
  non_repeatable_context context
  && List.mem
       (String.lowercase_ascii operation)
       [ "submit"; "press"; "click"; "upload"; "select"; "type_text"; "fill" ]

let procedure_repeatable (book : t) ~context (proc : procedure) =
  (* map-fmt02: the runner does not read provenance. Page pins and the procedure's own
     words decide replay. Learning reads the sidecar when it chooses a gate. *)
  List.for_all (fun (page : page) -> page.repeatable) book.pages
  && not
       (non_repeatable_context
          (String.concat " "
             (context :: proc.description
             :: List.filter_map (function Goal g -> Some g.goal | _ -> None) proc.steps)))

let draft_revision (book : t) =
  Digest.to_hex (Digest.string (Yojson.Safe.to_string (yojson_of_t book)))

let temporary_counter = Atomic.make 0

let atomic_write_json ~caps ~mode file json =
  try
    let rec create () =
      let temporary =
        Printf.sprintf "%s.%d.%d.tmp" file (Unix.getpid ())
          (Atomic.fetch_and_add temporary_counter 1)
      in
      try
        let fd =
          Cap_unix.openfile_write ~caps temporary
            [ Unix.O_CREAT; Unix.O_EXCL; Unix.O_WRONLY; Unix.O_CLOEXEC ]
            0o600
        in
        (temporary, Unix.out_channel_of_descr fd)
      with Unix.Unix_error (Unix.EEXIST, _, _) -> create ()
    in
    let temporary, ch = create () in
    Fun.protect
      ~finally:(fun () ->
        close_out_noerr ch;
        try Cap_sys.remove ~caps temporary with Sys_error _ -> ())
      (fun () ->
        output_string ch (Yojson.Safe.pretty_to_string json ^ "\n");
        flush ch;
        close_out ch;
        Cap_unix.chmod ~caps temporary mode;
        Cap_sys.rename ~caps temporary file;
        Ok ())
  with
  | Sys_error why -> Error (file ^ ": " ^ why)
  | Unix.Unix_error (code, fn, path) ->
      Error (fn ^ " " ^ path ^ ": " ^ Unix.error_message code)

let installation_mutex = Eio.Mutex.create ()
let installation_key = Eio.Fiber.create_key ()

let with_installation_lock ?(create = true) ?proposal ~caps fn =
  let lock_file root name fn =
    let* () = Config.ensure_dir ~caps root in
    try
      let descriptor =
        Cap_unix.openfile_write ~caps (Filename.concat root name)
          [ Unix.O_CREAT; Unix.O_WRONLY; Unix.O_CLOEXEC ]
          0o600
      in
      Fun.protect
        ~finally:(fun () -> Unix.close descriptor)
        (fun () ->
          Unix.lockf descriptor Unix.F_TLOCK 0;
          Fun.protect ~finally:(fun () -> Unix.lockf descriptor Unix.F_ULOCK 0) fn)
    with
    | Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) ->
        Error "playbook installation is busy; retry after the other installer finishes"
    | Unix.Unix_error (code, op, path) ->
        Error (op ^ " " ^ path ^ ": " ^ Unix.error_message code)
  in
  let locked () =
    let root = directory ~caps () in
    let with_proposal () =
      match proposal with
      | None -> fn ()
      | Some root -> lock_file root ".proposal.lock" fn
    in
    (* Proposing never creates an authored map directory. The source lock also
       covers a writer already publishing while first installation creates it. *)
    if create || Sys.file_exists root then lock_file root ".install.lock" with_proposal
    else with_proposal ()
  in
  let in_fiber =
    try
      ignore (Eio.Fiber.get installation_key);
      true
    with Effect.Unhandled _ -> false
  in
  if in_fiber then Eio.Mutex.use_rw ~protect:true installation_mutex locked else locked ()

let atomic_book ~caps file book =
  let mode = try (Unix.stat file).Unix.st_perm with Unix.Unix_error _ -> 0o600 in
  atomic_write_json ~caps ~mode file (yojson_of_t book)

let retire_unlocked ~caps ~site ~slug =
  let* book = installed_for_site ~caps site in
  match
    List.find_opt (fun (proc : procedure) -> proc.slug = slug) book.playbook.procedures
  with
  | None -> Error ("no installed procedure " ^ slug)
  | Some old ->
      let merged =
        {
          book.playbook with
          procedures =
            List.filter
              (fun (proc : procedure) -> proc.slug <> slug)
              book.playbook.procedures;
        }
      in
      let* () =
        if merged.procedures = [] then Ok ()
        else Result.map (fun _ -> ()) (revalidate ~caps book merged)
      in
      let* () =
        archive_procedure ~reason:"consecutive failed missions without successful repair"
          ~caps ~site old
      in
      atomic_book ~caps book.file merged

(* L31 run-xqh8: the checker's kind as the run's trace names it, which is also what
   [playbook check] reports a sentence resolved to. *)
let checker_name = function
  | Page_kind _ -> "page_kind"
  | Not_page_kind _ -> "not_page_kind"
  | Text _ -> "text"
  | Download _ -> "download"
  | No_dialog -> "no_dialog"
  | Row _ -> "row"
  | Judgment _ -> "judgment"

let yojson_of_checker = function
  | Page_kind name -> `Assoc [ ("checker", `String "page_kind"); ("kind", `String name) ]
  | Not_page_kind name ->
      `Assoc [ ("checker", `String "not_page_kind"); ("kind", `String name) ]
  | Text value -> `Assoc [ ("checker", `String "text"); ("text", `String value) ]
  | Download mime ->
      `Assoc
        [
          ("checker", `String "download");
          ("mime", match mime with None -> `Null | Some s -> `String s);
        ]
  | No_dialog -> `Assoc [ ("checker", `String "no_dialog") ]
  | Row (role, name) ->
      `Assoc
        [ ("checker", `String "row"); ("role", `String role); ("name", `String name) ]
  | Judgment sentence ->
      `Assoc [ ("checker", `String "judgment"); ("sentence", `String sentence) ]

(* run-k8bx: a failed verification replays the whole procedure once, never just
   its last step. The L31 loop owns the trace and records a second failure. *)
let retry_once ~execute ~verify =
  execute ();
  if verify () then true
  else (
    execute ();
    verify ())

let inspect ?(code = false) ?(provenances = []) book =
  let scripts =
    List.map
      (fun (script : script) ->
        `Assoc
          ([
             ("script", `String script.name);
             ("bytes", `Int (String.length script.code));
             ("returns", Shape.yojson_of_t script.returns);
           ]
          @ if code then [ ("code", `String script.code) ] else []))
      book.scripts
  in
  let checks =
    List.map
      (fun (slug, checkers) ->
        `Assoc
          [
            ("procedure", `String slug);
            ("checkers", `List (List.map yojson_of_checker checkers));
          ])
      book.checks
  in
  `Assoc
    [
      ("file", `String book.file);
      ("playbook", yojson_of_t book.playbook);
      ("scripts", `List scripts);
      ("resolved", `List checks);
      ( "provenances",
        `List
          (List.map
             (fun (slug, prov) ->
               `Assoc
                 [ ("slug", `String slug); ("provenance", yojson_of_provenance prov) ])
             provenances) );
    ]

type observation = {
  kind : string option;
  text : string;
  dialog : bool;
  rows : (string * string) list;
  downloads : (string * string * string) list;
}

(* run-2lei run-5rll: {name} is the format's one substitution, applied to a step's goal and
   to an expectation sentence from the values the run knows. A name with no value is left
   as it stands: the loader refused every argument a procedure does not declare, so an
   unfilled placeholder is a value the run has yet to ask for, not a defect. *)
let substitute values text =
  let buffer = Buffer.create (String.length text) in
  let rec scan i =
    if i >= String.length text then ()
    else if text.[i] = '{' then (
      match String.index_from_opt text (i + 1) '}' with
      | Some close -> (
          let name = String.sub text (i + 1) (close - i - 1) in
          match List.assoc_opt name values with
          | Some value ->
              Buffer.add_string buffer value;
              scan (close + 1)
          | None ->
              Buffer.add_char buffer text.[i];
              scan (i + 1))
      | None ->
          Buffer.add_char buffer text.[i];
          scan (i + 1))
    else (
      Buffer.add_char buffer text.[i];
      scan (i + 1))
  in
  scan 0;
  Buffer.contents buffer

(* run-tny5 run-vj48: each expectation as the sentence it is, next to the checker the
   loader resolved it to. The run substitutes its known arguments into the sentence
   first, so "the page shows {product}" is checked for the product the mission named; a
   substituted sentence the grammar no longer matches is judged by JEV rather than
   refused, because the authored form was validated at load. *)
let resolved ?(values = []) (book : t) (proc : procedure) =
  List.map
    (fun sentence ->
      let sentence = substitute values sentence in
      match resolve book.pages sentence with
      | Ok checker -> (sentence, checker)
      | Error _ -> (sentence, Judgment sentence))
    proc.expect

type checked = {
  expectation : string;
  checker : checker;
  passed : bool;
  score : float option;
}

(* run-l06s run-vbys run-xqh8: one checker against one observation. Judgment is never
   decided here — the score question is the runner's — so only the deterministic checkers
   are evaluated in code. *)
let passes checker (snapshot : observation) =
  match checker with
  | Page_kind kind -> snapshot.kind = Some kind
  | Not_page_kind kind ->
      Option.fold ~none:false ~some:(fun observed -> observed <> kind) snapshot.kind
  | Text text -> contains ~needle:text snapshot.text
  | Download mime ->
      List.exists
        (fun (name, media, state) ->
          state = "completed" && name <> ""
          && Option.fold ~none:true
               ~some:(fun required -> contains ~needle:required media)
               mime)
        snapshot.downloads
  | No_dialog -> not snapshot.dialog
  | Row (role, name) ->
      List.exists
        (fun (r, n) -> lower r = lower role && contains ~needle:name n)
        snapshot.rows
  | Judgment _ -> assert false

(* map-bjon: an authored procedure waits 5 s. A learned one waits 15 s unless the
   draft named its own bound, because a page-kind match can land while the result
   is still loading. *)
let expect_timeout_s = 5

(* run-l06s run-vbys: the bounded wait, keeping what each expectation came to, so the run's
   trace can say which checker decided it and — for a judgment — the score it carried. The
   result is the last observation's verdicts: the one that passed everything, or the one
   the deadline found. No sleeping after the deadline; each observation is fresh.
   map-bjon: a judgment is not final until the deadline. A pass scored against a page
   that moved during the score — a loading frame — is not accepted while time remains. *)
let await_results ~now ~sleep ~observe ~score ?(threshold = 0.8) ?(timeout_s = 5) checks =
  let deadline = now () +. float_of_int timeout_s in
  let has_judgment = List.exists (function _, Judgment _ -> true | _ -> false) checks in
  let evaluate snapshot =
    List.map
      (fun (sentence, checker) ->
        match checker with
        | Judgment _ ->
            let value = score sentence snapshot in
            {
              expectation = sentence;
              checker;
              passed = value >= threshold;
              score = Some value;
            }
        | checker ->
            {
              expectation = sentence;
              checker;
              passed = passes checker snapshot;
              score = None;
            })
      checks
  in
  let rec loop () =
    let snapshot = observe () in
    let results = evaluate snapshot in
    let passed = List.for_all (fun (result : checked) -> result.passed) results in
    if passed && has_judgment && now () < deadline then
      let fresh = observe () in
      if fresh.text <> snapshot.text then (
        sleep (min 0.1 (deadline -. now ()));
        loop ())
      else results
    else if passed then results
    else if now () >= deadline then results
    else (
      sleep (min 0.1 (deadline -. now ()));
      loop ())
  in
  loop ()

let await ~now ~sleep ~observe ~score ?threshold ?timeout_s checks =
  List.for_all
    (fun (result : checked) -> result.passed)
    (await_results ~now ~sleep ~observe ~score ?threshold ?timeout_s
       (List.map (fun checker -> ("", checker)) checks))

let check_draft (proc : procedure) =
  let require condition message = if condition then Ok () else Error message in
  let ( let* ) = Result.bind in
  let* () = require (trim proc.description <> "") "description must not be empty" in
  let* () =
    require
      (proc.expect <> [] && List.for_all (fun s -> trim s <> "") proc.expect)
      "expect must be a non-empty list of sentences"
  in
  let goals =
    List.length (List.filter (function Goal _ -> true | _ -> false) proc.steps)
  in
  require (goals >= 1) "a draft needs at least one goal step"

let write_provenance ~caps ~dir ~slug prov =
  atomic_write_json ~caps ~mode:0o600
    (Filename.concat dir (provenance_filename slug))
    (yojson_of_provenance prov)

let read_provenance ~caps path =
  if not (Sys.file_exists path) then Ok None
  else
    try
      let json =
        Cap_stdlib.In_channel.with_open_bin ~caps path Yojson.Safe.from_channel
      in
      match provenance_of_yojson json with
      | Ok prov -> Ok (Some prov)
      | Error why -> Error (path ^ ": " ^ why)
    with
    | Sys_error why -> Error (path ^ ": " ^ why)
    | Yojson.Json_error why -> Error (path ^ ": invalid JSON: " ^ why)

let learned_install ~caps ~from_dir ~to_dir ~file (book : t) (proc : procedure) =
  let src = Filename.concat from_dir (provenance_filename proc.slug) in
  let* prov = read_provenance ~caps src in
  match prov with
  | None -> Ok ()
  | Some prov ->
      let* () = check_goal_count ~minimum:1 ~file book proc in
      let* () =
        if
          List.exists (function Script _ -> true | _ -> false) proc.steps
          && ((not prov.repeatable) || prov.gate <> "replay")
        then
          Error
            (file ^ ": procedure " ^ proc.slug
           ^ ": proposed scripts require a repeatable replay-gate procedure")
        else Ok ()
      in
      let* () =
        List.fold_left
          (fun result step ->
            let* () = result in
            match step with
            | Script step -> (
                match
                  List.assoc_opt step.script (Option.value ~default:[] book.scripts)
                with
                | None -> Ok ()
                | Some decl -> (
                    match decl.source with
                    | None -> Ok ()
                    | Some source -> check_proposed_script source))
            | _ -> Ok ())
          (Ok ()) proc.steps
      in
      write_provenance ~caps ~dir:to_dir ~slug:proc.slug prov

let accept_unlocked ?revision ?(replayed_scripts = []) ~caps path =
  let ( let* ) = Result.bind in
  let* json =
    try Ok (Cap_stdlib.In_channel.with_open_bin ~caps path Yojson.Safe.from_channel) with
    | Sys_error why -> Error (path ^ ": " ^ why)
    | Yojson.Json_error why -> Error (path ^ ": invalid JSON: " ^ why)
  in
  if match json with `Assoc fields -> List.mem_assoc "entry" fields | _ -> false then
    let* discovered = of_json ~file:path json in
    let draft = discovered.playbook in
    let* () =
      match revision with
      | Some expected when draft_revision draft <> expected ->
          Error "stale draft revision; nothing was installed"
      | _ -> Ok ()
    in
    (* map-op08: manual acceptance cannot bypass successful script replay. *)
    let* () =
      let required = List.map (fun (s : script) -> s.name) discovered.scripts in
      if List.for_all (fun name -> List.mem name replayed_scripts) required then Ok ()
      else
        Error
          (path
         ^ ": proposed scripts must run successfully through the replay gate before \
            installation")
    in
    let* existing =
      match installed_for_site ~caps draft.site with
      | Ok book -> Ok (Some book)
      | Error why when String.starts_with ~prefix:"no installed playbook" why -> Ok None
      | Error why -> Error why
    in
    let merged, destination, dir, replaced =
      match existing with
      | None ->
          let dir = Filename.concat (directory ~caps ()) draft.site in
          (draft, Filename.concat dir "playbook.json", Some dir, false)
      | Some book ->
          let pages =
            book.playbook.pages
            @ List.filter
                (fun (page : page) ->
                  not
                    (List.exists
                       (fun (old : page) -> old.name = page.name)
                       book.playbook.pages))
                draft.pages
          in
          let procedures =
            List.fold_left
              (fun current (proc : procedure) ->
                if List.exists (fun (old : procedure) -> old.slug = proc.slug) current
                then
                  List.map
                    (fun (old : procedure) -> if old.slug = proc.slug then proc else old)
                    current
                else current @ [ proc ])
              book.playbook.procedures draft.procedures
          in
          let existing_scripts = Option.value ~default:[] book.playbook.scripts in
          let scripts =
            existing_scripts
            @ List.filter
                (fun (name, _) -> not (List.mem_assoc name existing_scripts))
                (Option.value ~default:[] draft.scripts)
          in
          ( {
              book.playbook with
              pages;
              procedures;
              scripts = (if scripts = [] then None else Some scripts);
            },
            book.file,
            book.dir,
            true )
    in
    let* _ =
      validate ~file:destination
        ~dir:(Option.map (fun dir -> (reads caps, dir)) dir)
        merged
    in
    let* () =
      match existing with
      | None -> Ok ()
      | Some old ->
          List.fold_left
            (fun result (proc : procedure) ->
              let* () = result in
              if
                List.exists
                  (fun (replacement : procedure) -> replacement.slug = proc.slug)
                  draft.procedures
              then archive_procedure ~caps ~site:draft.site proc
              else Ok ())
            (Ok ()) old.playbook.procedures
    in
    let* () = Config.ensure_dir ~caps (Filename.dirname destination) in
    let* () =
      List.fold_left
        (fun result (proc : procedure) ->
          let* () = result in
          learned_install ~caps ~from_dir:(Filename.dirname path)
            ~to_dir:(Filename.dirname destination)
            ~file:destination merged proc)
        (Ok ()) draft.procedures
    in
    let* () = atomic_book ~caps destination merged in
    Ok { site = draft.site; slug = "*"; playbook = destination; replaced }
  else
    let* proposal = read_proposal ~caps path in
    let* (book : loaded) = installed_for_site ~caps proposal.site in
    let* () =
      match revision with
      | Some expected
        when draft_revision { book.playbook with procedures = [ proposal.procedure ] }
             <> expected ->
          Error "stale draft revision; nothing was installed"
      | _ -> Ok ()
    in
    let replaced =
      List.exists
        (fun (proc : procedure) -> proc.slug = proposal.procedure.slug)
        book.playbook.procedures
    in
    let procedures =
      if replaced then
        List.map
          (fun (proc : procedure) ->
            if proc.slug = proposal.procedure.slug then proposal.procedure else proc)
          book.playbook.procedures
      else book.playbook.procedures @ [ proposal.procedure ]
    in
    let merged = { book.playbook with procedures } in
    let* (_ : loaded) = revalidate ~caps book merged in
    let* () =
      if replaced then
        archive_procedure ~caps ~site:proposal.site
          (List.find
             (fun (proc : procedure) -> proc.slug = proposal.procedure.slug)
             book.playbook.procedures)
      else Ok ()
    in
    let* () =
      learned_install ~caps ~from_dir:(Filename.dirname path)
        ~to_dir:(Filename.dirname book.file) ~file:book.file merged proposal.procedure
    in
    let* () = atomic_book ~caps book.file merged in
    Ok
      {
        site = proposal.site;
        slug = proposal.procedure.slug;
        playbook = book.file;
        replaced;
      }

let accept ?revision ?(consume = false) ?(replayed_scripts = []) ~caps path =
  (* Reject model-authored scripts before creating any installed-map state. Read
     again under the lock so a replacement cannot evade the validated merge. *)
  let* () =
    try
      match Cap_stdlib.In_channel.with_open_bin ~caps path Yojson.Safe.from_channel with
      | `Assoc fields when List.mem_assoc "procedures" fields -> (
          match List.assoc_opt "scripts" fields with
          | None | Some `Null -> Ok ()
          | Some _ when replayed_scripts <> [] -> Ok ()
          | Some _ ->
              Error
                "proposed scripts must run successfully through the replay gate before \
                 installation")
      | _ -> Ok ()
    with
    | Sys_error why -> Error (path ^ ": " ^ why)
    | Yojson.Json_error why -> Error (path ^ ": invalid JSON: " ^ why)
  in
  let proposal =
    if consume || Option.is_some revision then Some (Filename.dirname path) else None
  in
  with_installation_lock ?proposal ~caps (fun () ->
      let* accepted = accept_unlocked ?revision ~replayed_scripts ~caps path in
      (if consume && path <> accepted.playbook then
         try Cap_sys.remove ~caps path with Sys_error _ -> ());
      Ok accepted)

let check_draft_revision ~caps path = function
  | None -> Ok ()
  | Some expected ->
      let* current =
        try
          let json =
            Cap_stdlib.In_channel.with_open_bin ~caps path Yojson.Safe.from_channel
          in
          of_json ~file:path json
        with Sys_error why | Yojson.Json_error why -> Error why
      in
      if draft_revision current.playbook = expected then Ok ()
      else Error "stale draft revision; replacement proposal was left unchanged"

let retire ~caps ~site ~slug =
  with_installation_lock ~caps (fun () -> retire_unlocked ~caps ~site ~slug)

let retire_draft ~caps ~file ~revision ~site ~slug =
  with_installation_lock ~proposal:(Filename.dirname file) ~caps (fun () ->
      let* () = check_draft_revision ~caps file (Some revision) in
      retire_unlocked ~caps ~site ~slug)

(* map-b3kk map-2l5q: writers and consumers share the install lock. A trial failure
   may replace only the revision it inspected; successful acceptance consumes that
   precise revision before another compiler can replace its pathname. *)

let propose ?book ?revision ?provenance ~caps ~site (proc : procedure) =
  let directory = proposed_directory ~caps () in
  let path = Filename.concat directory (site ^ "-" ^ proc.slug ^ ".json") in
  let* () = Config.ensure_dir ~caps directory in
  with_installation_lock ~create:false ~proposal:directory ~caps (fun () ->
      let* () = check_draft_revision ~caps path revision in
      let json =
        match book with
        | None -> yojson_of_proposal { site; procedure = proc }
        | Some book -> yojson_of_t { book with procedures = [ proc ] }
      in
      let* () = atomic_write_json ~caps ~mode:0o600 path json in
      let* () =
        match provenance with
        | None -> Ok ()
        | Some prov -> write_provenance ~caps ~dir:directory ~slug:proc.slug prov
      in
      Ok path)

let archive_proposal ~revision ~caps path =
  with_installation_lock ~create:false ~proposal:(Filename.dirname path) ~caps (fun () ->
      let* () = check_draft_revision ~caps path (Some revision) in
      let destination = Filename.concat (proposed_directory ~caps ()) "retired" in
      let* () = Config.ensure_dir ~caps destination in
      try
        Cap_sys.rename ~caps path
          (Filename.concat destination (Filename.basename path ^ "." ^ revision));
        Ok ()
      with Sys_error why -> Error why)
