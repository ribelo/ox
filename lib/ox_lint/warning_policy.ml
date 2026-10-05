open Ocaml_common

type setting = Warning | Fatal
type directive = setting * string
type decision = Clean | Restriction of string | Unverified of string

module Numbers = Set.Make (Int)

let universe =
  List.fold_left
    (fun set (description : Warnings.description) -> Numbers.add description.number set)
    Numbers.empty Warnings.descriptions

let group letter =
  let numbers =
    match Char.uppercase_ascii letter with
    | 'A' -> Numbers.elements universe
    | 'C' -> [ 1; 2 ]
    | 'D' -> [ 3 ]
    | 'E' -> [ 4 ]
    | 'F' -> [ 5 ]
    | 'K' -> List.init 8 (fun i -> i + 32)
    | 'L' -> [ 6 ]
    | 'M' -> [ 7 ]
    | 'P' -> [ 8 ]
    | 'R' -> [ 9 ]
    | 'S' -> [ 10 ]
    | 'U' -> [ 11; 12 ]
    | 'V' -> [ 13 ]
    | 'X' -> List.init 11 (fun i -> i + 14) @ [ 30 ]
    | 'Y' -> [ 26 ]
    | 'Z' -> [ 27 ]
    | _ -> []
  in
  Numbers.of_list numbers

let apply (active, fatal) (setting, specification) =
  (* Let the linked compiler reject syntax it cannot interpret. Its mutable warning
     state is always restored; this predicate does not change compiler globals. *)
  Warnings.with_state (Warnings.backup ()) (fun () ->
      ignore (Warnings.parse_options (setting = Fatal) specification));
  let length = String.length specification in
  let digit c = c >= '0' && c <= '9' in
  let rec number stop =
    if stop < length && digit specification.[stop] then number (stop + 1) else stop
  in
  let modify sign selected (active, fatal) =
    let update set =
      if sign = '-' then Numbers.diff set selected else Numbers.union set selected
    in
    match (setting, sign) with
    | (Warning | Fatal), '@' -> (update active, update fatal)
    | Warning, _ -> (update active, fatal)
    | Fatal, _ -> (active, update fatal)
  in
  let names =
    List.concat_map
      (fun (description : Warnings.description) ->
        List.map (fun name -> (name, description.number)) description.names)
      Warnings.descriptions
    |> List.sort (fun (a, _) (b, _) -> Int.compare (String.length b) (String.length a))
  in
  let named pos =
    List.find_opt
      (fun (name, _) ->
        let stop = pos + String.length name in
        stop <= length
        && String.sub specification pos (String.length name) = name
        && (stop = length || List.mem specification.[stop] [ '+'; '-'; '@' ]))
      names
  in
  let rec loop pos sign state =
    if pos = length then state
    else
      match specification.[pos] with
      | ('+' | '-' | '@') as sign -> loop (pos + 1) sign state
      | c when digit c ->
          let stop = number pos in
          let first = int_of_string (String.sub specification pos (stop - pos)) in
          let last, next =
            if stop + 1 < length && String.sub specification stop 2 = ".." then
              let next = number (stop + 2) in
              (int_of_string (String.sub specification (stop + 2) (next - stop - 2)), next)
            else (first, stop)
          in
          let selected = Numbers.filter (fun n -> n >= first && n <= last) universe in
          loop next sign (modify sign selected state)
      | c -> (
          match named pos with
          | Some (name, n) ->
              loop
                (pos + String.length name)
                sign
                (modify sign (Numbers.singleton n) state)
          | None ->
              let casing = if c >= 'A' && c <= 'Z' then '+' else '-' in
              let effective =
                if pos > 0 && List.mem specification.[pos - 1] [ '+'; '-'; '@' ] then
                  specification.[pos - 1]
                else casing
              in
              loop (pos + 1) effective (modify effective (group c) state))
  in
  loop 0 '+' (active, fatal)

(* Audited Dune 3.22.2+ox defaults change at language 3.21. *)
let dune_standard = [ "-warn-error"; "+a" ]

let compiler_defaults =
  apply (Numbers.empty, Numbers.empty) (Warning, Warnings.defaults_w) |> fun state ->
  apply state (Fatal, Warnings.defaults_warn_error)

let baseline =
  let active, fatal = apply compiler_defaults (Fatal, "+a") in
  (active, Numbers.inter active fatal)

let evaluate_policy required directives =
  try
    let active, fatal = List.fold_left apply baseline directives in
    let required_active, required_fatal = required in
    let missing =
      Numbers.union
        (Numbers.diff required_active active)
        (Numbers.diff required_fatal fatal)
    in
    if Numbers.is_empty active then Restriction "all compiler warnings are disabled"
    else if Numbers.is_empty missing then Clean
    else
      Restriction
        ("required active/fatal warnings disabled: "
        ^ String.concat "," (List.map string_of_int (Numbers.elements missing)))
  with Arg.Bad message | Failure message | Invalid_argument message ->
    Unverified ("unsupported compiler warning specification: " ^ message)

let evaluate directives = evaluate_policy baseline directives
let evaluate_attached ~inherited attached = evaluate (inherited @ List.rev attached)

let arguments args =
  let rec loop acc = function
    | (("-w" | "-warn-error") as option) :: value :: rest ->
        let setting = if option = "-w" then Warning else Fatal in
        loop ((setting, value) :: acc) rest
    | [ ("-w" | "-warn-error") ] -> Error "missing compiler warning argument"
    | ("-args" | "-args0") :: _ -> Error "unexpanded compiler argument file"
    | _ :: rest -> loop acc rest
    | [] -> Ok (List.rev acc)
  in
  loop [] args

let reconcile_standard standard ~recorded ~flags ~compiler_flags =
  let expand standard = function
    | None -> Ok standard
    | Some words ->
        if
          List.exists
            (fun word ->
              String.contains word '%' || String.contains word '\\'
              || (String.starts_with ~prefix:":" word && word <> ":standard"))
            words
        then Error "unresolved Dune ordered-set expansion"
        else
          Ok
            (List.concat_map
               (fun word -> if word = ":standard" then standard else [ word ])
               words)
  in
  match (expand standard flags, expand [] compiler_flags) with
  | Error message, _ | _, Error message -> Unverified message
  | Ok common, Ok specific -> (
      match (arguments recorded, arguments (common @ specific)) with
      | Error message, _ | _, Error message -> Unverified message
      | Ok actual, Ok expected -> (
          try
            let initial = compiler_defaults in
            let a, f = List.fold_left apply initial actual in
            let b, g = List.fold_left apply initial expected in
            if Numbers.equal a b && Numbers.equal f g then Clean
            else
              Unverified
                "Dune policy content disagrees with recorded compiler warning settings"
          with Arg.Bad message | Failure message | Invalid_argument message ->
            Unverified ("unsupported Dune warning specification: " ^ message)))

let reconcile ~recorded ~flags ~compiler_flags =
  reconcile_standard dune_standard ~recorded ~flags ~compiler_flags

let attribute_setting = function
  | "warning" | "ocaml.warning" -> Some Warning
  | "warnerror" | "ocaml.warnerror" -> Some Fatal
  | _ -> None

let payload_string = function
  | Parsetree.PStr
      [
        {
          pstr_desc =
            Pstr_eval
              ( {
                  pexp_desc = Pexp_constant { pconst_desc = Pconst_string (s, _, _); _ };
                  _;
                },
                _ );
          _;
        };
      ] ->
      Some s
  | _ -> None

let check_source ~caps ~source ~directives ~report ~undecided =
  let current = ref directives in
  let pending = ref None in
  let flush () =
    match !pending with
    | None -> ()
    | Some loc ->
        pending := None;
        report loc (evaluate !current)
  in
  let attribute_directive (attribute : Parsetree.attribute) =
    match attribute_setting attribute.attr_name.txt with
    | None -> None
    | Some setting -> (
        match payload_string attribute.attr_payload with
        | None ->
            undecided attribute.attr_loc "nonliteral source warning attribute";
            None
        | Some specification -> Some (setting, specification))
  in
  let scoped f =
    let saved = !current and location = !pending in
    Fun.protect
      ~finally:(fun () ->
        current := saved;
        pending := location)
      (fun () ->
        f ();
        flush ())
  in
  let floating attribute =
    match attribute_directive attribute with
    | None -> ()
    | Some directive ->
        current := !current @ [ directive ];
        pending := Some attribute.Parsetree.attr_loc
  in
  let base = Ast_iterator.default_iterator in
  let iterator =
    {
      base with
      attribute =
        (fun _ attribute ->
          match attribute_directive attribute with
          | None -> ()
          | Some directive ->
              report attribute.attr_loc (evaluate (!current @ [ directive ])));
      attributes =
        (fun _ attributes ->
          let changes = List.filter_map attribute_directive attributes in
          match (attributes, changes) with
          | attribute :: _, _ :: _ ->
              report attribute.Parsetree.attr_loc
                (evaluate_attached ~inherited:!current changes)
          | _ -> ());
      structure = (fun self structure -> scoped (fun () -> base.structure self structure));
      signature = (fun self signature -> scoped (fun () -> base.signature self signature));
      structure_item =
        (fun self item ->
          match item.Parsetree.pstr_desc with
          | Pstr_attribute attribute -> floating attribute
          | _ ->
              flush ();
              base.structure_item self item);
      signature_item =
        (fun self item ->
          match item.Parsetree.psig_desc with
          | Psig_attribute attribute -> floating attribute
          | _ ->
              flush ();
              base.signature_item self item);
    }
  in
  (* Attribute inspection needs parsing only, never a fresh compiler environment.
     Preserve the checked artifact's implicit opens and installed load path. *)
  Lexer.handle_docstrings := true;
  Docstrings.init ();
  Lexer.init ();
  let channel = Ox_caps.Cap_stdlib.open_in ~caps source in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let lexbuf = Lexing.from_channel channel in
      Location.init lexbuf source;
      if Filename.check_suffix source ".mli" then
        iterator.signature iterator (Parse.interface lexbuf)
      else iterator.structure iterator (Parse.implementation lexbuf))

let read_text ~caps path =
  let channel = Ox_caps.Cap_stdlib.open_in ~caps path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> In_channel.input_all channel)

type sexp = Atom of string | List of sexp list

let parse_dune text =
  let length = String.length text in
  let rec items nested pos acc =
    if pos = length then
      if nested then failwith "truncated Dune list" else (List.rev acc, pos)
    else
      match text.[pos] with
      | ' ' | '\n' | '\r' | '\t' -> items nested (pos + 1) acc
      | ';' ->
          items nested
            (Option.value (String.index_from_opt text pos '\n') ~default:length)
            acc
      | ')' ->
          if nested then (List.rev acc, pos + 1) else failwith "unexpected Dune close"
      | '(' ->
          let values, next = items true (pos + 1) [] in
          items nested next (List values :: acc)
      | '"' ->
          let rec stop i =
            if i >= length then failwith "truncated Dune string"
            else if text.[i] = '\\' then stop (i + 2)
            else if text.[i] = '"' then i
            else stop (i + 1)
          in
          let last = stop (pos + 1) in
          let atom = Scanf.unescaped (String.sub text (pos + 1) (last - pos - 1)) in
          items nested (last + 1) (Atom atom :: acc)
      | _ ->
          let rec stop i =
            if i = length || List.mem text.[i] [ ' '; '\n'; '\r'; '\t'; '('; ')'; ';' ]
            then i
            else stop (i + 1)
          in
          let next = stop pos in
          items nested next (Atom (String.sub text pos (next - pos)) :: acc)
  in
  fst (items false 0 [])

let rec atoms = function
  | Atom atom -> [ atom ]
  | List values -> List.concat_map atoms values

let contains text fragment =
  let rec loop pos =
    pos + String.length fragment <= String.length text
    && (String.sub text pos (String.length fragment) = fragment || loop (pos + 1))
  in
  loop 0

let regular_file ~caps path =
  ignore caps#fs_read;
  try (Unix.stat path).Unix.st_kind = Unix.S_REG
  with Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR), _, _) -> false

let source_standard ~caps source =
  let rec ascend directory =
    let project = Filename.concat directory "dune-project" in
    if regular_file ~caps project then
      match
        parse_dune (read_text ~caps project)
        |> List.filter_map (function
          | List [ Atom "lang"; Atom "dune"; Atom version ] -> Some version
          | _ -> None)
      with
      | [ "3.20" ] -> [ "-w"; "@1..3@5..28@31..39@43@46..47@49..57@61..62@67@69-40" ]
      | [ "3.21" ] | [ "3.22" ] -> dune_standard
      | [ version ] -> failwith ("unverified Dune language standard: " ^ version)
      | _ -> failwith "unverified missing/ambiguous Dune language declaration"
    else
      let parent = Filename.dirname directory in
      if parent = directory then dune_standard else ascend parent
  in
  ascend (Filename.dirname source)

let compiled_scopes artifact =
  let args = Array.to_list artifact.Artifact.info.cmt_args in
  let rec outputs = function
    | "-o" :: path :: rest -> path :: outputs rest
    | _ :: rest -> outputs rest
    | [] -> []
  in
  List.concat_map
    (fun path ->
      List.filter_map
        (fun component ->
          List.find_map
            (fun suffix ->
              let length = String.length component - String.length suffix - 1 in
              if
                length > 0
                && String.starts_with ~prefix:"." component
                && String.ends_with ~suffix component
              then Some (String.sub component 1 length)
              else None)
            [ ".objs"; ".eobjs" ])
        (String.split_on_char '/' path))
    (outputs args)

let stanza_names fields =
  List.concat_map
    (function
      | List (Atom ("name" | "names") :: values) -> List.concat_map atoms values | _ -> [])
    fields

let generated_empty_source ~caps artifact =
  let physical = Artifact.source artifact in
  match (artifact.Artifact.info.cmt_annots, Artifact.workspace ~caps artifact.path) with
  | Interface signature, Some root when signature.sig_items = [] ->
      let prefix = root ^ "/_build/default/" in
      if not (String.starts_with ~prefix physical && Filename.check_suffix physical ".mli")
      then None
      else
        let relative =
          String.sub physical (String.length prefix)
            (String.length physical - String.length prefix)
        in
        let relative =
          if Filename.check_suffix relative ".pp.mli" then
            String.sub relative 0 (String.length relative - 7) ^ ".mli"
          else relative
        in
        let logical = Filename.concat root relative in
        if
          regular_file ~caps logical
          || String.trim (read_text ~caps physical) <> "(* Auto-generated by Dune *)"
        then None
        else
          let name = Filename.remove_extension (Filename.basename logical) in
          let unit_name = Compilation_unit.name_as_string artifact.info.cmt_modname in
          let file = Filename.concat (Filename.dirname logical) "dune" in
          let scopes = compiled_scopes artifact in
          let owned =
            regular_file ~caps file
            && List.exists
                 (function
                   | List
                       (Atom ("test" | "tests" | "executable" | "executables") :: fields)
                     ->
                       let names = stanza_names fields in
                       let empty =
                         List.filter_map
                           (function
                             | List (Atom "empty_module_interface" :: values) ->
                                 Some values
                             | _ -> None)
                           fields
                       in
                       List.mem name names
                       && List.exists (fun name -> List.mem name scopes) names
                       && (empty = [] || empty = [ [ Atom "true" ] ])
                   | _ -> false)
                 (parse_dune (read_text ~caps file))
          in
          if
            (not owned)
            || List.exists
                 (fun part -> List.mem part [ ""; "."; ".." ])
                 (String.split_on_char '/' relative)
            || unit_name <> "Dune__exe__" ^ String.capitalize_ascii name
            || Filename.remove_extension (Filename.basename artifact.path)
               <> String.uncapitalize_ascii unit_name
          then failwith "unverified generated empty interface producer/unit ownership"
          else begin
            Artifact.check ~caps ~source:physical artifact;
            Some (physical, logical)
          end
  | _ -> None

let check_dune ~caps ~artifact ~source ~standard ~undecided =
  let args = Array.to_list artifact.Artifact.info.cmt_args in
  let compiled_scopes = compiled_scopes artifact in
  let compiled_scope name = List.mem name compiled_scopes in
  let compiler =
    match args with compiler :: _ -> Filename.basename compiler | [] -> ""
  in
  let byte = contains compiler "ocamlc" in
  let native = contains compiler "ocamlopt" in
  let inspect path =
    let loc = Location.in_file path in
    let applicable field =
      field = "flags"
      || (field = "ocamlc_flags" && byte)
      || (field = "ocamlopt_flags" && native)
    in
    let literal_values values =
      let values = match values with [ List words ] -> words | words -> words in
      if List.for_all (function Atom _ -> true | List _ -> false) values then
        Ok (List.concat_map atoms values)
      else Error "unsupported nested Dune ordered-set expression"
    in
    let field_values name fields =
      match
        List.filter_map
          (function
            | List (Atom field :: values) when field = name -> Some values | _ -> None)
          fields
      with
      | [] -> Ok None
      | [ values ] -> (
          match literal_values values with
          | Ok words -> Ok (Some words)
          | Error message -> Error message)
      | _ -> Error ("duplicate Dune " ^ name ^ " fields")
    in
    let rec visit scope = function
      | List
          (Atom (("library" | "test" | "tests" | "executable" | "executables") as kind)
          :: fields) ->
          let names = stanza_names fields in
          let selected =
            Filename.dirname path = Filename.dirname source
            && List.exists compiled_scope names
          in
          let disjoint =
            compiled_scopes <> [] && names <> []
            && List.for_all
                 (fun name ->
                   name <> ""
                   && String.for_all
                        (function
                          | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '.' -> true
                          | _ -> false)
                        name)
                 names
            && not (List.exists compiled_scope names)
          in
          let scope = kind ^ " " ^ String.concat "," names in
          (if selected then
             let specific = if byte then "ocamlc_flags" else "ocamlopt_flags" in
             match (field_values "flags" fields, field_values specific fields) with
             | Error message, _ | _, Error message ->
                 undecided loc ("unverified Dune " ^ scope ^ ": " ^ message)
             | Ok flags, Ok compiler_flags -> (
                 match
                   reconcile_standard standard ~recorded:args ~flags ~compiler_flags
                 with
                 | Clean -> ()
                 | Restriction message | Unverified message ->
                     undecided loc ("unverified Dune " ^ scope ^ ": " ^ message)));
          if not disjoint then
            List.iter
              (function
                | List (Atom field :: _) when selected && applicable field -> ()
                | field -> visit scope field)
              fields
      (* C/C++ compiler and linker flags cannot alter OCaml warning policy. *)
      | List (Atom ("foreign_stubs" | "foreign_library" | "c_library_flags") :: _) -> ()
      | List [ Atom "env"; List profiles ] -> List.iter (visit "profile") profiles
      | List (Atom (("dev" | "_" | "release") as profile) :: fields)
        when scope = "profile" ->
          List.iter (visit ("profile " ^ profile)) fields
      | List (Atom (("flags" | "ocamlc_flags" | "ocamlopt_flags") as field) :: _) ->
          undecided loc
            ("unverified Dune " ^ scope ^ " " ^ field
           ^ ": no exact checked compiler scope")
      | List (Atom ("include" | "include_subdirs") :: _) ->
          undecided loc "unverified Dune include/subdirectory compiler policy"
      | List values -> List.iter (visit scope) values
      | Atom _ -> ()
    in
    let parsed =
      try Ok (parse_dune (read_text ~caps path))
      with Sys_error message | Failure message | Scanf.Scan_failure message ->
        Error message
    in
    match parsed with
    | Ok stanzas -> List.iter (visit "stanza") stanzas
    | Error message -> undecided loc ("unverified Dune policy: " ^ message)
  in
  let rec ascend directory =
    let dune = Filename.concat directory "dune" in
    if regular_file ~caps dune then inspect dune;
    let legacy = Filename.concat directory "dune.inc" in
    if regular_file ~caps legacy then
      undecided (Location.in_file legacy) "unverified included Dune policy";
    let project = Filename.concat directory "dune-project" in
    let parent = Filename.dirname directory in
    if (not (regular_file ~caps project)) && parent <> directory then ascend parent
  in
  ascend (Filename.dirname source)

let check ~caps ~artifact ~emit ~undecided =
  let source = Artifact.source artifact in
  let loc = Location.in_file source in
  let report loc = function
    | Clean -> ()
    | Restriction message -> emit loc message
    | Unverified message -> undecided loc message
  in
  let args = Array.to_list artifact.Artifact.info.cmt_args in
  match arguments args with
  | Error message -> undecided loc message
  | Ok directives -> (
      if args = [] then undecided loc "missing recorded compiler arguments"
      else
        let directives =
          (Warning, Warnings.defaults_w)
          :: (Fatal, Warnings.defaults_warn_error)
          :: directives
        in
        report loc (evaluate directives);
        let authored =
          try
            let source, policy_source =
              match generated_empty_source ~caps artifact with
              | Some pair -> pair
              | None ->
                  let source = Artifact.authored_source ~caps artifact in
                  (source, source)
            in
            Ok (source, policy_source, source_standard ~caps policy_source)
          with Sys_error message | Failure message -> Error message
        in
        match authored with
        | Error message -> undecided loc ("unverified source warning policy: " ^ message)
        | Ok (source, policy_source, standard) ->
            check_source ~caps ~source ~directives ~report ~undecided;
            check_dune ~caps ~artifact ~source:policy_source ~standard ~undecided)
