(* ^nlint-jm8g ^nlint-2nwm: findings are data; parser/annotation failures are evidence errors. *)
open Ocaml_common

let usage =
  "ox-lint [--rules RULE]... [--require-typed] [--self-check] [--root DIR] PATH...\n\
  \  Build first: dune build @install; dune build @check for executable modules\n\
  \  Example: ox-lint --require-typed --rules ox-discarded-result lib/\n\
  \  PATH is an .ml/.mli source, a directory, or a .cmt/.cmti annotation.\n\
  \  Exit 0: clean; 1: findings; 2: invalid arguments or incomplete evidence."

let rec files path =
  if Sys.is_directory path then
    Array.to_list (Sys.readdir path)
    |> List.sort String.compare
    |> List.concat_map (fun name ->
        if name = "_build" || name = ".git" then [] else files (Filename.concat path name))
  else if List.exists (Filename.check_suffix path) [ ".ml"; ".mli"; ".cmt"; ".cmti" ] then
    [ path ]
  else []

let rec data_root dir =
  if
    Sys.file_exists (Filename.concat dir "dune-project")
    || Sys.file_exists (Filename.concat dir "test/lint/violating")
  then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else data_root parent

let rec evidence_root dir =
  (* Either marker claims this bundle: missing evidence must not trigger a checkout fallback. *)
  if
    Sys.file_exists (Filename.concat dir "docs/rules")
    || Sys.file_exists (Filename.concat dir "test/lint/violating")
  then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else evidence_root parent

let self_check_root override =
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
        match evidence_root directory with
        | Some root -> root
        | None -> Option.value (evidence_root (Sys.getcwd ())) ~default:installed)

let () =
  let ids, paths, self_check, require_typed = (ref [], ref [], ref false, ref false) in
  (* ^ncapslint-x3gi ^ncapslint-87ld: the gate selects typed rules, never a lexer. *)
  let caps_gate, allows = (ref false, ref []) in
  let root_override = ref None in
  Arg.parse
    [
      ( "--caps-gate",
        Arg.Set caps_gate,
        " Run capability policy (lib/packages/bin by default)" );
      ( "--allow",
        Arg.String (fun glob -> allows := glob :: !allows),
        "GLOB Exclude a gate path (reason belongs in caller documentation)" );
      ( "--rules",
        Arg.String (fun id -> ids := id :: !ids),
        "RULE Select a rule (repeatable)" );
      ( "--require-typed",
        Arg.Set require_typed,
        " Require fresh typed evidence; optional only in --caps-gate mode" );
      ( "--root",
        Arg.String (fun root -> root_override := Some root),
        "DIR  rule pages and self-check fixture root (overrides automatic lookup)" );
      ( "--self-check",
        Arg.Set self_check,
        " Check every rule's replacement, fixtures and documentation" );
    ]
    (fun path -> paths := path :: !paths)
    usage;
  let findings, failures = (ref 0, ref 0) in
  let undecided = ref 0 in
  let sites = Hashtbl.create 64 in
  let fail ?(typed = false) path ex =
    if typed then incr undecided;
    if not (typed && !caps_gate && not !require_typed) then incr failures;
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
    let message = String.map (function '\n' | '\r' -> ' ' | c -> c) message in
    Printf.eprintf "%s:1: ox-lint: %s\n" path message
  in
  (try
     if !caps_gate && !paths = [] then
       paths := List.filter Sys.file_exists [ "lib"; "packages"; "bin" ];
     if !allows <> [] && not !caps_gate then invalid_arg "--allow requires --caps-gate";
     let rules =
       Rules.select !ids
       |> List.filter (fun rule ->
           (not !caps_gate) || String.starts_with ~prefix:"ox-caps-" rule.Rules.id)
     in
     if !self_check then begin
       let root = self_check_root !root_override in
       let errors = Rules.self_check ~root Rules.all @ Caps_policy.self_check root in
       List.iter (fun message -> fail "ox-lint --self-check" (Failure message)) errors;
       if errors = [] then
         Printf.printf
           "ox-lint --self-check: %d rule(s), replacement/violating/clean/docs present\n"
           (List.length Rules.all)
     end;
     if !paths = [] && not !self_check then invalid_arg "no PATH supplied; see --help";
     let inputs =
       List.concat_map
         (fun path ->
           let xs = files path in
           if xs = [] then invalid_arg ("no OCaml sources at " ^ path);
           xs)
         (List.rev !paths)
       |> List.sort_uniq String.compare
       |> List.filter (fun path ->
           (not !caps_gate) || not (Caps_policy.excluded !allows path))
     in
     if !caps_gate then
       Caps_policy.check_dune (List.rev !paths) (fun path line ->
           incr findings;
           Printf.printf "%s:%d: ox-caps-mint: forbidden dependency ox_caps.door\n" path
             line);
     List.iter
       (fun input ->
         try
           let direct =
             Filename.check_suffix input ".cmt" || Filename.check_suffix input ".cmti"
           in
           let artifact = if direct then Some (Artifact.read input) else None in
           let source =
             match artifact with Some t -> Artifact.source t | None -> input
           in
           if (not direct) && Artifact.membership source = Artifact.Not_built then
             Printf.printf "%s:1: ox-lint: not built (not in any Dune target)\n" source
           else begin
             (* ^nlintc-j03j ^nlintc-7be1: apply policy to the original source, not its annotation. *)
             let root =
               Option.value (data_root (Filename.dirname source)) ~default:(Sys.getcwd ())
             in
             let rules = List.filter (Rules.applies ~root ~source) rules in
             let emit rule loc =
               let key =
                 ( source,
                   loc.Location.loc_start.pos_lnum,
                   loc.loc_start.pos_cnum,
                   rule.Rules.id )
               in
               if not (Hashtbl.mem sites key) then begin
                 Hashtbl.add sites key ();
                 incr findings;
                 Printf.printf "%s:%d: %s: %s\n" source loc.loc_start.pos_lnum rule.id
                   rule.message
               end
             in
             Syntax.walk source (fun context iterator ->
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
                   match artifact with Some t -> t | None -> Artifact.find source
                 in
                 Artifact.check ~source t;
                 Artifact.setup t;
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
                   rules
               with ex -> fail ~typed:true input ex
               end
           end
         with ex -> fail input ex)
       inputs;
     if !caps_gate then
       Printf.eprintf "caps-gate: %d findings; %d modules with typed rules undecided%s\n"
         !findings !undecided
         (if !require_typed then " (typed evidence required)"
          else " (build first for typed coverage)")
   with ex -> fail "ox-lint" ex);
  exit (if !failures > 0 then 2 else if !findings > 0 then 1 else 0)
