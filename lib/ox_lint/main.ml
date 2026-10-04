(* ^nlint-jm8g ^nlint-2nwm: findings are data; parser/annotation failures are evidence errors. *)
open Ocaml_common
open Ox_caps

let usage =
  "ox-lint [--repo-gate] [--rules RULE]... [--require-typed] [--self-check] [--root \
   DIR]   PATH...\n\
  \  Build first: dune build @install; dune build @check for executable modules\n\
  \  Example: ox-lint --require-typed --rules ox-discarded-result lib/\n\
  \  PATH is an .ml/.mli source, a directory, or a .cmt/.cmti annotation.\n\
  \  Exit 0: clean; 1: findings; 2: invalid arguments or incomplete evidence."

(* ^ncapslint-2606: discovery respects project boundaries; named paths cross them. *)
let rec files ~caps ~default_scan ~scan_root ~record ~ignored_paths ~directory_cycles
    ~seen path =
  if
    default_scan && path <> scan_root && Sys.is_directory path
    && Sys.file_exists (Filename.concat path "dune-project")
  then begin
    record (path ^ "/") "excluded" "nested-project";
    []
  end
  else if Sys.is_directory path then
    let stat = Unix.stat path in
    let identity = (stat.Unix.st_dev, stat.st_ino) in
    if List.mem identity seen then begin
      incr directory_cycles;
      record (path ^ "/") "excluded" "directory-cycle";
      []
    end
    else
      let seen = identity :: seen in
      let names =
        Array.to_list (Cap_sys.readdir ~caps path) |> List.sort String.compare
      in
      let ignored = Artifact.ignored ~caps ~directory:path names in
      List.concat_map
        (fun name ->
          if List.mem name ignored then begin
            incr ignored_paths;
            let ignored_path = Filename.concat path name in
            let ignored_path =
              if (Unix.lstat ignored_path).Unix.st_kind = Unix.S_DIR then
                ignored_path ^ "/"
              else ignored_path
            in
            record ignored_path "excluded" "ignored";
            []
          end
          else if name = "_build" || name = ".git" then []
          else
            files ~caps ~default_scan ~scan_root ~record ~ignored_paths ~directory_cycles
              ~seen (Filename.concat path name))
        names
  else if List.exists (Filename.check_suffix path) [ ".ml"; ".mli"; ".cmt"; ".cmti" ] then
    [ path ]
  else []

let absolute path =
  let path =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  String.split_on_char '/' path
  |> List.fold_left
       (fun parts -> function
         | "." | "" -> parts
         | ".." -> ( match parts with [] -> [] | _ :: rest -> rest)
         | part -> part :: parts)
       []
  |> List.rev |> String.concat "/"
  |> fun path -> "/" ^ path

let beneath directory path =
  let directory, path = (absolute directory, absolute path) in
  directory = path || String.starts_with ~prefix:(directory ^ "/") path

let rec data_root ~(caps : < Cap.fs_read ; .. >) dir =
  ignore caps#fs_read;
  if
    Sys.file_exists (Filename.concat dir "dune-project")
    || Sys.file_exists (Filename.concat dir "test/lint/violating")
  then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else data_root ~caps parent

let rec evidence_root ~(caps : < Cap.fs_read ; .. >) dir =
  ignore caps#fs_read;
  (* Either marker claims this bundle: missing evidence must not trigger a checkout fallback. *)
  if
    Sys.file_exists (Filename.concat dir "docs/rules")
    || Sys.file_exists (Filename.concat dir "test/lint/violating")
  then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else evidence_root ~caps parent

let self_check_root ~(caps : < Cap.fs_read ; .. >) override =
  match override with
  | Some root -> root
  | None -> (
      let executable =
        if Filename.is_relative Sys.executable_name then
          Filename.concat (Sys.getcwd ()) Sys.executable_name
        else Sys.executable_name
      in
      let directory = Filename.dirname executable in
      let installed = Filename.concat (Filename.dirname directory) "share/ox_lint" in
      if Filename.basename directory = "bin" && Filename.basename executable = "ox-lint"
      then installed
      else if Sys.file_exists installed then installed
      else
        match evidence_root ~caps directory with
        | Some root -> root
        | None -> Option.value (evidence_root ~caps (Sys.getcwd ())) ~default:installed)

let run ~(caps : < Cap.fork ; Cap.exec ; Cap.fs_read ; Cap.stdout ; Cap.stderr ; .. >) =
  let ids, paths, self_check, require_typed = (ref [], ref [], ref false, ref false) in
  (* ^nlint-r01u ^ncapslint-x3gi: the repository gate selects every registered rule. *)
  let repo_gate, allows = (ref false, ref []) in
  let root_override = ref None in
  let inventory = ref false in
  let options =
    [
      ( "--repo-gate",
        Arg.Set repo_gate,
        " Decide all registered rules (whole workspace by default)" );
      ("--caps-gate", Arg.Set repo_gate, " Alias for --repo-gate");
      ( "--rules",
        Arg.String (fun id -> ids := id :: !ids),
        "RULE Select a rule (repeatable)" );
      ( "--require-typed",
        Arg.Set require_typed,
        " Require fresh typed evidence; optional only in --repo-gate mode" );
      ( "--allow",
        Arg.String (fun glob -> allows := glob :: !allows),
        "GLOB Exclude a gate path (shipped policy has no entries)" );
      ( "--root",
        Arg.String (fun root -> root_override := Some root),
        "DIR  rule pages and self-check fixture root (overrides automatic lookup)" );
      ( "--inventory",
        Arg.Set inventory,
        " Print PATH\tDECISION\tREASON; findings remain on stderr" );
      ( "--self-check",
        Arg.Set self_check,
        " Check every rule's replacement, fixtures and documentation" );
    ]
  in
  let parsed =
    try
      Arg.parse_argv Sys.argv options (fun path -> paths := path :: !paths) usage;
      Ok ()
    with
    | Arg.Help message -> Error (`Help message)
    | Arg.Bad message -> Error (`Bad message)
  in
  match parsed with
  | Error (`Help message) ->
      Cap_stdlib.print_string ~caps message;
      0
  | Error (`Bad message) ->
      Cap_stdlib.prerr_string ~caps message;
      2
  | Ok () ->
      let findings, failures = (ref 0, ref 0) in
      let undecided = ref 0 in
      let data_only, empty_paths, ignored_paths, directory_cycles =
        (ref 0, ref 0, ref 0, ref 0)
      in
      let decisions = Hashtbl.create 128 in
      let record path decision reason =
        if !inventory then
          match Hashtbl.find_opt decisions path with
          | Some ("undecided", previous) ->
              if decision = "undecided" && previous <> reason then
                Hashtbl.replace decisions path (decision, previous ^ " | " ^ reason)
          | Some ("excluded", _) when decision = "excluded" && reason = "no-ocaml" -> ()
          | _ -> Hashtbl.replace decisions path (decision, reason)
      in
      let default_scan = !repo_gate && !paths = [] in
      let scan_root =
        Option.value (Artifact.workspace ~caps (Sys.getcwd ())) ~default:(Sys.getcwd ())
      in
      let sites = Hashtbl.create 64 in
      let producers = Hashtbl.create 16 in
      let with_producer path message =
        match Hashtbl.find_opt producers (absolute path) with
        | None -> message
        | Some producer -> message ^ " (generated by " ^ producer ^ ")"
      in
      let undecided_paths = Hashtbl.create 16 in
      let fail ?(typed = false) ?(fatal = false) path ex =
        if typed && not (Hashtbl.mem undecided_paths (absolute path)) then begin
          Hashtbl.add undecided_paths (absolute path) ();
          incr undecided
        end;
        if fatal || not (typed && !repo_gate && not !require_typed) then incr failures;
        let message =
          match ex with
          | Failure s | Invalid_argument s | Sys_error s -> s
          | _ -> (
              (* ^nlintc-du4v: ask whether the compiler recognises this exception,
             rather than catch and suppress an exception from its printer. *)
              match Location.error_of_exn ex with
              | Some (`Ok error) -> Format.asprintf "%a" Location.print_report error
              | Some `Already_displayed -> "error already displayed"
              | None -> Printexc.to_string ex)
        in
        let message = with_producer path message in
        let message = String.map (function '\n' | '\r' -> ' ' | c -> c) message in
        record path "undecided" message;
        Cap_stdlib.eprintf ~caps "%s:1: ox-lint: %s\n" path message
      in
      (try
         if default_scan then paths := [ scan_root ];
         if !allows <> [] && not !repo_gate then
           invalid_arg "--allow requires --repo-gate (or --caps-gate)";
         let rules = Rules.select ~caps !ids in
         if !self_check then begin
           let root = self_check_root ~caps !root_override in
           let errors =
             Rules.self_check ~caps ~root (Rules.all ~caps)
             @ Caps_policy.self_check ~caps root
           in
           List.iter (fun message -> fail "ox-lint --self-check" (Failure message)) errors;
           if errors = [] then
             Cap_stdlib.printf ~caps
               "ox-lint --self-check: %d rule(s), replacement/violating/clean/docs present\n"
               (List.length (Rules.all ~caps))
         end;
         if !paths = [] && not !self_check then invalid_arg "no PATH supplied; see --help";
         (* ^nlintcov-q6n2: named and discovered generated evidence share provenance. *)
         let typed_requested =
           !require_typed || List.exists (fun r -> Option.is_some r.Rules.typed) rules
         in
         let selections =
           List.rev !paths
           |> List.filter_map (fun input ->
               try
                 let directory = Sys.is_directory input in
                 let source =
                   if
                     Filename.check_suffix input ".cmt"
                     || Filename.check_suffix input ".cmti"
                   then Artifact.source (Artifact.read ~caps input)
                   else input
                 in
                 Some (input, directory, source)
               with ex ->
                 fail ~typed:typed_requested ~fatal:true input ex;
                 None)
         in
         let unresolved = Hashtbl.create 16 in
         let generated =
           if
             not
               (!require_typed
               || List.exists (fun (_, directory, _) -> directory) selections)
           then []
           else
             selections
             (* ^nlint-2nwm ^nlintcov-q6n2: named source files require their own
                evidence, not an unrelated workspace-wide generated inventory.
                Keep that query for directory discovery and source-less build inputs. *)
             |> List.filter_map (fun (input, directory, source) ->
                 Option.bind (Artifact.workspace ~caps input) (fun root ->
                     let source = absolute source in
                     let build = Filename.concat root "_build/default/" in
                     let generated =
                       if String.starts_with ~prefix:build source then
                         let relative =
                           String.sub source (String.length build)
                             (String.length source - String.length build)
                         in
                         let relative =
                           if Filename.check_suffix relative ".pp.ml" then
                             Filename.chop_suffix relative ".pp.ml" ^ ".ml"
                           else if Filename.check_suffix relative ".pp.mli" then
                             Filename.chop_suffix relative ".pp.mli" ^ ".mli"
                           else relative
                         in
                         not (Sys.file_exists (Filename.concat root relative))
                       else false
                     in
                     if directory || generated then Some root else None))
             |> List.map absolute |> List.sort_uniq String.compare
             |> List.concat_map (fun root ->
                 match Artifact.generated_sources ~caps ~root with
                 | Error message ->
                     fail ~typed:true
                       (Filename.concat root "(generated sources)")
                       (Failure message);
                     []
                 | Ok entries ->
                     List.filter_map
                       (fun (entry : Artifact.generated) ->
                         let build = Filename.concat root "_build/default/" in
                         let counterpart =
                           if String.starts_with ~prefix:build entry.path then
                             Filename.concat root
                               (String.sub entry.path (String.length build)
                                  (String.length entry.path - String.length build))
                           else entry.path
                         in
                         let matches =
                           List.filter
                             (fun (input, directory, source) ->
                               if directory then
                                 beneath input counterpart || beneath input entry.path
                               else absolute source = absolute entry.path)
                             selections
                         in
                         if matches = [] then None
                         else
                           match entry.producer with
                           | None ->
                               Hashtbl.replace unresolved (absolute entry.path) ();
                               List.iter
                                 (fun (input, directory, _) ->
                                   if not directory then
                                     Hashtbl.replace unresolved (absolute input) ())
                                 matches;
                               fail ~typed:true ~fatal:true entry.path
                                 (Failure
                                    "generated source has unresolved producer provenance");
                               None
                           | Some producer ->
                               Hashtbl.replace producers (absolute entry.path) producer;
                               List.iter
                                 (fun (input, directory, _) ->
                                   if not directory then
                                     Hashtbl.replace producers (absolute input) producer)
                                 matches;
                               if List.exists (fun (_, directory, _) -> directory) matches
                               then Some entry.path
                               else None)
                       entries)
         in
         let rebuilt = ref 0 in
         (* ^nlintcov-q6n2 ^nlint-r01u: finish mutating inventory before rebuilding.
             An explicit scan must still expose missing/stale supplied annotations. *)
         if !repo_gate && default_scan then
           List.iter
             (fun root ->
               try
                 Artifact.rebuild_check ~caps root;
                 incr rebuilt
               with ex -> fail ~typed:true ~fatal:true root ex)
             (List.map (fun (_, _, workspace) -> workspace) selections
             |> List.sort_uniq String.compare);
         let inputs =
           List.concat_map
             (fun path ->
               let entry = Unix.lstat path in
               if
                 entry.Unix.st_kind = Unix.S_DIR
                 && Artifact.ignored ~caps ~directory:(Filename.dirname path)
                      [ Filename.basename path ]
                    <> []
               then begin
                 incr ignored_paths;
                 record (path ^ "/") "excluded" "ignored";
                 []
               end
               else begin
                 let xs =
                   files ~caps ~default_scan ~scan_root ~record ~ignored_paths
                     ~directory_cycles ~seen:[] path
                 in
                 if xs = [] then begin
                   incr empty_paths;
                   record (path ^ "/") "excluded" "no-ocaml"
                 end;
                 xs
               end)
             (List.map (fun (input, _, _) -> input) selections)
           |> fun sources ->
           sources @ generated |> List.sort_uniq String.compare
           |> List.filter (fun path -> not (Hashtbl.mem unresolved (absolute path)))
           |> List.filter (fun path ->
               if !repo_gate && Caps_policy.excluded !allows path then begin
                 record path "excluded" "explicit-allow";
                 false
               end
               else true)
         in
         if !repo_gate && List.exists (fun rule -> rule.Rules.id = "ox-caps-mint") rules
         then
           Caps_policy.check_dune ~caps (List.rev !paths) (fun path line ->
               incr findings;
               let print = if !inventory then Cap_stdlib.eprintf else Cap_stdlib.printf in
               print ~caps "%s:%d: ox-caps-mint: forbidden dependency ox_caps.door\n" path
                 line);
         List.iter
           (fun input ->
             try
               let direct =
                 Filename.check_suffix input ".cmt" || Filename.check_suffix input ".cmti"
               in
               let artifact = if direct then Some (Artifact.read ~caps input) else None in
               let source =
                 match artifact with Some t -> Artifact.source t | None -> input
               in
               let membership =
                 if direct then Artifact.Unknown else Artifact.membership ~caps source
               in
               if default_scan && membership = Artifact.Data_only then begin
                 incr data_only;
                 record source "excluded" "data-only"
               end
               else if membership = Artifact.Not_built then begin
                 record source "excluded" "not-built";
                 let print =
                   if !inventory then Cap_stdlib.eprintf ~caps
                   else Cap_stdlib.printf ~caps
                 in
                 print
                   "%s:1: ox-lint: not built (not in any Dune target); absent from \
                    workspace and @check rules\n"
                   source
               end
               else begin
                 (* ^nlintc-j03j ^nlintc-7be1: apply policy to the original source, not its annotation. *)
                 let root =
                   Option.value
                     (data_root ~caps (Filename.dirname source))
                     ~default:(Sys.getcwd ())
                 in
                 let rules = List.filter (Rules.applies ~root ~source) rules in
                 let decided = ref true in
                 let emit_message rule loc message =
                   let key =
                     ( source,
                       loc.Location.loc_start.pos_lnum,
                       loc.loc_start.pos_cnum,
                       rule.Rules.id )
                   in
                   if not (Hashtbl.mem sites key) then begin
                     Hashtbl.add sites key ();
                     incr findings;
                     let print =
                       if !inventory then Cap_stdlib.eprintf ~caps
                       else Cap_stdlib.printf ~caps
                     in
                     print "%s:%d: %s: %s\n" source loc.loc_start.pos_lnum rule.id
                       (with_producer input message)
                   end
                 in
                 let emit rule loc = emit_message rule loc rule.Rules.message in
                 Syntax.walk ~caps source (fun context iterator ->
                     List.fold_left
                       (fun iterator rule ->
                         match rule.Rules.source with
                         | Some make -> make (emit rule) context iterator
                         | None -> iterator)
                       iterator rules);
                 if
                   List.exists (fun rule -> Option.is_some rule.Rules.typed) rules
                   || !require_typed
                 then
                   begin try
                     let t =
                       match artifact with
                       | Some t -> t
                       | None -> Artifact.find ~caps source
                     in
                     Artifact.check ~caps ~source t;
                     Artifact.setup ~caps t;
                     List.iter
                       (fun rule ->
                         match rule.Rules.typed with
                         | None -> ()
                         | Some make -> (
                             let iterator = make (emit rule) in
                             match t.info.cmt_annots with
                             | Implementation tree -> iterator.structure iterator tree
                             | Interface tree -> iterator.signature iterator tree
                             | _ -> assert false))
                       rules;
                     match t.info.cmt_annots with
                     | Interface _
                       when List.exists
                              (fun r ->
                                r.Rules.id = "ox-val-behaviour"
                                || r.id = "ox-cancel-safety")
                              rules ->
                         Interface_docs.truth ~caps ~source ~artifact:t
                           ~rules:(List.map (fun r -> r.Rules.id) rules)
                           ~emit:(fun id loc message ->
                             let rule = List.find (fun r -> r.Rules.id = id) rules in
                             emit_message rule loc message)
                           ~undecided:(fun loc message ->
                             decided := false;
                             fail ~typed:true input
                               (Failure
                                  (Printf.sprintf "line %d: %s"
                                     loc.Location.loc_start.pos_lnum message)))
                     | _ -> ()
                   with ex ->
                     decided := false;
                     fail ~typed:true input ex
                   end;
                 if !decided then record input "decided" ""
               end
             with ex -> fail ~typed:typed_requested ~fatal:true input ex)
           inputs;
         if !repo_gate then begin
           let selected = List.length rules in
           let dormant = List.length (List.filter Rules.dormant rules) in
           Cap_stdlib.eprintf ~caps
             "repo-gate: %d registered rules selected (%d active, %d dormant); %d \
              findings; %d modules with typed rules undecided; %d data-only files out of \
              scope; %d paths with no OCaml sources; %d ignored paths skipped; %d \
              directory cycles skipped; rebuilt @check in %d workspace%s%s\n"
             selected (selected - dormant) dormant !findings !undecided !data_only
             !empty_paths !ignored_paths !directory_cycles !rebuilt
             (if !rebuilt = 1 then "" else "s")
             (if !require_typed then " (typed evidence required)"
              else " (build first for typed coverage)")
         end
         else if !empty_paths > 0 || !ignored_paths > 0 || !directory_cycles > 0 then
           Cap_stdlib.eprintf ~caps
             "ox-lint: %d paths with no OCaml sources; %d ignored paths skipped; %d \
              directory cycles skipped\n"
             !empty_paths !ignored_paths !directory_cycles
       with ex -> fail "ox-lint" ex);
      if !inventory then
        Hashtbl.to_seq decisions |> List.of_seq
        |> List.sort (fun (a, _) (b, _) -> String.compare a b)
        |> List.iter (fun (path, (decision, reason)) ->
            Cap_stdlib.printf ~caps "%s\t%s\t%s\n" path decision reason);
      if !failures > 0 then 2 else if !findings > 0 then 1 else 0

let main
    ~(caps :
       < Cap.fork ; Cap.exec ; Cap.fs_read ; Cap.stdout ; Cap.stderr ; Cap.exit ; .. >) =
  Cap_stdlib.exit ~caps (run ~caps)

let () = main ~caps:(Ox_caps_door.powerbox ())
