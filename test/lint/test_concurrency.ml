(* ^nlintc-du4v ^nlintc-g6k3 ^nlintc-j03j ^nlintc-7be1 ^nlintc-4gjw ^nlintc-kdcl. *)
(* ^safe-pcom ^safe-28t6: dormant-policy and evidence validation survive -noassert. *)
open Ocaml_common

let count ~caps (rule : Rules.t) dir =
  let source = if dir = "violating" then rule.Rules.violating else rule.clean in
  let source = Filename.concat dir (Filename.basename source) in
  let sites = ref [] in
  let emit loc = sites := loc.Location.loc_start.Lexing.pos_lnum :: !sites in
  Option.iter
    (fun make -> Syntax.walk ~caps source (fun context base -> make emit context base))
    rule.source;
  let inspect run =
    let unit_name =
      String.capitalize_ascii (Filename.remove_extension (Filename.basename source))
    in
    let annotation =
      Printf.sprintf "%s/.concurrency_%s.objs/byte/concurrency_%s__%s.cmt" dir dir dir
        unit_name
    in
    let artifact = Artifact.read ~caps annotation in
    Artifact.check ~caps ~source artifact;
    Artifact.setup ~caps artifact;
    run artifact
  in
  Option.iter
    (fun make ->
      inspect (fun artifact ->
          let iterator : Tast_iterator.iterator = make emit in
          match artifact.info.cmt_annots with
          | Implementation tree -> iterator.structure iterator tree
          | _ -> failwith "expected implementation fixture"))
    rule.typed;
  Option.iter
    (fun run ->
      inspect (fun artifact ->
          run
            ~emit:(fun loc _message -> emit loc)
            ~undecided:(fun loc message ->
              failwith
                (Printf.sprintf "%s:%d: %s undecided: %s" source
                   loc.Location.loc_start.Lexing.pos_lnum rule.id message))
            artifact))
    rule.evidence;
  List.sort Int.compare !sites

(* ^nlintc-du4v ^nlintc-kdcl: actual named entries, not a library wearing an executable name. *)
let check_entries ~caps =
  List.iter
    (fun (name, annotation, expected) ->
      let source = "entry/" ^ name ^ ".ml" in
      let artifact = Artifact.read ~caps ("entry/" ^ annotation) in
      Artifact.check ~caps ~source artifact;
      Artifact.setup ~caps artifact;
      let sites = ref [] in
      let iterator =
        Concurrency.catch_all ~caps (fun loc ->
            sites := loc.Location.loc_start.Lexing.pos_lnum :: !sites)
      in
      (match artifact.info.cmt_annots with
      | Implementation tree -> iterator.structure iterator tree
      | _ -> failwith "expected entry implementation");
      let actual = List.sort Int.compare !sites in
      if actual <> expected then
        failwith
          (Printf.sprintf "%s entry: expected [%s], got [%s]" name
             (String.concat ";" (List.map string_of_int expected))
             (String.concat ";" (List.map string_of_int actual))))
    [
      ( "exit_entry",
        ".exit_entry.eobjs/byte/dune__exe__Exit_entry.cmt",
        [ 54; 64; 75; 84; 96; 104; 107; 112; 124 ] );
      ( "app_entry",
        ".exit_entry.eobjs/byte/dune__exe__App_entry.cmt",
        [ 17; 22; 28; 35; 40 ] );
      ("exit_utility", ".exit_entry.eobjs/byte/dune__exe__Exit_utility.cmt", [ 7 ]);
      ("entry_library", ".entry_library.objs/byte/entry_library.cmt", [ 7 ]);
    ]

let run ~(caps : < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout ; .. >) () =
  let expectations =
    [
      ( "ox-catch-all",
        [ 6; 14; 15; 16; 17; 18; 21; 25; 31; 37; 38; 40; 44; 48; 53; 59; 66; 70; 73; 76 ]
      );
      ("ox-suspending-finalizer", [ 4; 5; 10; 14; 20 ]);
      ("ox-stdlib-lock", [ 6; 11; 18; 21; 29; 34; 41 ]);
      ("ox-raw-concurrency", [ 4; 5; 6; 7; 8; 9; 10; 14 ]);
      ("ox-public-exception", [ 3; 6 ]);
      ("ox-obj-magic", [ 4; 8; 12; 14 ]);
      ("ox-race-deadline", [ 5; 15; 23; 29 ]);
    ]
  in
  List.iter
    (fun (id, expected) ->
      let rule = List.hd (Rules.select ~caps [ id ]) in
      let actual = count ~caps rule "violating" in
      if actual <> expected then
        failwith
          (Printf.sprintf "%s: expected [%s], got [%s]" id
             (String.concat ";" (List.map string_of_int expected))
             (String.concat ";" (List.map string_of_int actual)));
      let clean = count ~caps rule "clean" in
      if clean <> [] then
        failwith
          (Printf.sprintf "%s clean fixture: [%s]" id
             (String.concat ";" (List.map string_of_int clean))))
    expectations;
  check_entries ~caps;
  let root = Sys.getcwd () in
  assert (Rules.allowances = []);
  let raw = List.hd (Rules.select ~caps [ "ox-raw-concurrency" ]) in
  List.iter
    (fun source ->
      if Rules.applies ~root ~source raw then
        failwith ("dormant raw policy applies: " ^ source))
    [ "lib/ox/core.ml"; "lib/http/client.ml"; "/tmp/consumer.ml" ];
  (* ^safe-j6t8: prevention activates transactions in ordinary and audit scans. *)
  let transaction = List.hd (Rules.select ~caps [ "ox-transaction-runner" ]) in
  if Rules.dormant transaction || Rules.dormant ~audit:true transaction then
    failwith "transaction prevention policy is dormant";
  if
    (not (Rules.applies ~root ~source:"/tmp/consumer.ml" transaction))
    || (not (Rules.applies ~audit:true ~root ~source:"/tmp/consumer.ml" transaction))
    || Rules.applies ~audit:true ~root ~source:"/tmp/consumer.ml" raw
  then failwith "explicit audit policy disagrees with applicability";
  if Rules.self_check ~caps ~root:"../.." (Rules.all ~caps) <> [] then
    failwith "concurrency rule evidence rejected";
  Ox_caps.Cap_stdlib.print_endline ~caps
    "seven concurrency rules: exact violating sites, clean fixtures, allowances and \
     dormant raw policy: pass"

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout >) in
  run ~caps ()
