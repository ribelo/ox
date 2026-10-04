(* ^nlint-jm8g ^nlint-2nwm: findings are data; parser/annotation failures are evidence errors. *)
open Ocaml_common

let usage =
  "ox-lint [--rules RULE]... [--require-typed] [--self-check] PATH...\n\
  \  Build first: dune build @install\n\
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

let () =
  let ids, paths, self_check, require_typed = (ref [], ref [], ref false, ref false) in
  Arg.parse
    [
      ( "--rules",
        Arg.String (fun id -> ids := id :: !ids),
        "RULE Select a rule (repeatable)" );
      ( "--require-typed",
        Arg.Set require_typed,
        " Require complete fresh typed evidence (always enforced for typed rules)" );
      ( "--self-check",
        Arg.Set self_check,
        " Check every rule's replacement, fixtures and documentation" );
    ]
    (fun path -> paths := path :: !paths)
    usage;
  let findings, failures = (ref 0, ref 0) in
  let fail path ex =
    incr failures;
    let message =
      match ex with
      | Failure s | Invalid_argument s | Sys_error s -> s
      | _ -> (
          try Format.asprintf "%a" Location.report_exception ex
          with _ -> Printexc.to_string ex)
    in
    let message = String.map (function '\n' | '\r' -> ' ' | c -> c) message in
    Printf.eprintf "%s:1: ox-lint: %s\n" path message
  in
  (try
     let rules = Rules.select !ids in
     if !self_check then begin
       let directory = Filename.dirname Sys.executable_name in
       let root =
         if Filename.basename Sys.executable_name = "ox-lint" then directory
         else
           match data_root directory with
           | Some root -> root
           | None ->
               Option.value
                 (data_root (Sys.getcwd ()))
                 ~default:(Filename.dirname Sys.executable_name)
       in
       let errors = Rules.self_check ~root Rules.all in
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
     in
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
           let emit rule loc =
             incr findings;
             Printf.printf "%s:%d: %s: %s\n" source loc.Location.loc_start.Lexing.pos_lnum
               rule.Rules.id rule.message
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
           then begin
             let t = match artifact with Some t -> t | None -> Artifact.find source in
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
           end
         with ex -> fail input ex)
       inputs
   with ex -> fail "ox-lint" ex);
  exit (if !failures > 0 then 2 else if !findings > 0 then 1 else 0)
