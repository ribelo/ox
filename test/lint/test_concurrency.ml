(* ^nlintc-du4v ^nlintc-g6k3 ^nlintc-j03j ^nlintc-7be1 ^nlintc-4gjw ^nlintc-kdcl. *)
open Ocaml_common

let count ~caps (rule : Rules.t) dir =
  let source = if dir = "violating" then rule.Rules.violating else rule.clean in
  let source = Filename.concat dir (Filename.basename source) in
  let sites = ref [] in
  let emit loc = sites := loc.Location.loc_start.Lexing.pos_lnum :: !sites in
  Option.iter
    (fun make -> Syntax.walk ~caps source (fun context base -> make emit context base))
    rule.source;
  Option.iter
    (fun make ->
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
      let iterator : Tast_iterator.iterator = make emit in
      match artifact.info.cmt_annots with
      | Implementation tree -> iterator.structure iterator tree
      | _ -> failwith "expected implementation fixture")
    rule.typed;
  List.sort Int.compare !sites

let run ~(caps : < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout ; .. >) () =
  let expectations =
    [
      ("ox-catch-all", [ 6; 14; 15; 16; 17; 18; 21; 25; 31 ]);
      ("ox-suspending-finalizer", [ 4; 5; 10; 14; 20 ]);
      ("ox-stdlib-lock", [ 6; 11; 18; 21; 29; 34 ]);
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
  let root = Sys.getcwd () in
  assert (Rules.allowances = []);
  let raw = List.hd (Rules.select ~caps [ "ox-raw-concurrency" ]) in
  List.iter
    (fun source -> assert (not (Rules.applies ~root ~source raw)))
    [ "lib/ox/core.ml"; "lib/http/client.ml"; "/tmp/consumer.ml" ];
  assert (Rules.self_check ~caps ~root:"../.." (Rules.all ~caps) = []);
  Ox_caps.Cap_stdlib.print_endline ~caps
    "seven concurrency rules: exact violating sites, clean fixtures, allowances and \
     dormant raw policy: pass"

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout >) in
  run ~caps ()
