(* ^safe-1kqm ^safe-gm8y ^safe-l2jj ^safe-y047: actual compiler evidence. *)
let run ~(caps : < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout >) =
  let directory =
    match Array.to_list Sys.argv with
    | [ _; directory ] -> directory
    | _ -> failwith "usage: test_codec_seams SCRATCH_PROJECT"
  in
  let check name extension expected_findings expected_unknown =
    let source = Filename.concat directory (name ^ "." ^ extension) in
    let annotation =
      Filename.concat directory
        ("_build/default/.codec_seams_fixtures.objs/byte/codec_seams_fixtures__"
       ^ String.capitalize_ascii name
        ^ if extension = "mli" then ".cmti" else ".cmt")
    in
    let artifact = Artifact.read ~caps annotation in
    Artifact.check ~caps ~source artifact;
    Artifact.setup ~caps artifact;
    let findings = ref [] and unknown = ref [] in
    Codec_seams.check ~caps artifact
      ~emit:(fun loc message ->
        findings :=
          (loc.Ocaml_common.Location.loc_start.Lexing.pos_lnum, message) :: !findings)
      ~undecided:(fun loc message ->
        unknown :=
          (loc.Ocaml_common.Location.loc_start.Lexing.pos_lnum, message) :: !unknown);
    let lines entries = List.sort_uniq Int.compare (List.map fst entries) in
    let expect kind actual expected =
      if lines actual <> expected then
        failwith
          (Printf.sprintf "%s %s expected [%s], got [%s]: %s" source kind
             (String.concat ";" (List.map string_of_int expected))
             (String.concat ";" (List.map string_of_int (lines actual)))
             (String.concat " | " (List.map snd actual)))
    in
    expect "findings" !findings expected_findings;
    expect "undecided" !unknown expected_unknown
  in
  check "good" "mli" [] [];
  check "raw" "mli" [ 2; 4; 5; 6; 7; 8; 9; 10; 13; 14 ] [];
  check "opaque" "mli" [] [ 2; 3 ];
  check "impostor" "mli" [] [ 2; 3 ];
  check "json_named" "mli" [] [];
  check "malformed" "mli" [ 2 ] [ 1 ];
  check "misplaced" "mli" [] [ 1 ];
  check "implementation_marker" "ml" [] [ 1 ];
  check "seams" "mli" [] [];
  check "nested" "mli" [ 4 ] [];
  check "duplicate" "mli" [ 3 ] [ 1; 2 ];
  check "copied" "mli" [ 2; 3 ] [];
  check "horizon" "mli" [] [ 3; 4; 5; 6 ];
  Ox_caps.Cap_stdlib.printf ~caps "codec-seams compiler controls passed\n"

let () = run ~caps:(Ox_test.powerbox () :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout >)
