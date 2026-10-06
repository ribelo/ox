open Ocaml_common

type certainty = Finding | Unverified

let sites ~caps source annotation =
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let diagnostics = ref [] in
  let record category loc message =
    if message = "" then failwith "empty named diagnostic";
    let first = loc.Location.loc_start and last = loc.Location.loc_end in
    if first.Lexing.pos_fname <> last.Lexing.pos_fname then
      failwith "diagnostic crossed physical source files";
    diagnostics :=
      ( first.pos_fname,
        first.pos_lnum,
        first.pos_cnum - first.pos_bol,
        last.pos_lnum,
        last.pos_cnum - last.pos_bol,
        category )
      :: !diagnostics
  in
  let iterator =
    Monotonic_elapsed_time.check ~caps ~emit:(record Finding)
      ~undecided:(record Unverified)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | Interface tree -> iterator.signature iterator tree
  | _ -> failwith "missing complete typed evidence");
  (* Physical sites and categories are compared literally, without deduplication. *)
  List.sort Stdlib.compare !diagnostics

let show (file, line, column, last_line, last_column, category) =
  Printf.sprintf "%s:%d:%d-%d:%d:%s" file line column last_line last_column
    (match category with Finding -> "wall-elapsed" | Unverified -> "unverified")

let expect label expected actual =
  if List.sort Stdlib.compare expected <> actual then
    failwith
      (label ^ ": expected ["
      ^ String.concat ";" (List.map show expected)
      ^ "], got ["
      ^ String.concat ";" (List.map show actual)
      ^ "]")

let wall =
  [
    ("wall.ml", 3, 2, 3, 31, Finding);
    ("wall.ml", 7, 2, 7, 27, Finding);
    ("wall.ml", 9, 18, 9, 59, Finding);
    ("wall.ml", 12, 2, 12, 70, Finding);
    ("wall.ml", 16, 2, 16, 51, Finding);
  ]

let unknown =
  [ ("unknown.ml", 3, 26, 3, 77, Unverified); ("unknown.ml", 7, 2, 7, 40, Unverified) ]

let wrong_site_red label actual =
  match actual with
  | [] -> failwith "red control requires diagnostics"
  | (file, line, column, last_line, last_column, category) :: rest ->
      let wrong = (file, line, column + 1, last_line, last_column, category) :: rest in
      if List.length wrong <> List.length actual then failwith "changed red count";
      let rejected =
        try
          expect label wrong actual;
          false
        with Failure _ -> true
      in
      if not rejected then failwith "same-count wrong physical site was accepted";
      let wrong_file =
        ("wrong.ml", line, column, last_line, last_column, category) :: rest
      in
      let rejected =
        try
          expect label wrong_file actual;
          false
        with Failure _ -> true
      in
      if not rejected then failwith "same-count wrong physical file was accepted"

let fixtures ~caps directory =
  let check name expected =
    let file extension = Filename.concat directory (name ^ "." ^ extension) in
    expect (name ^ " MLI-first") [] (sites ~caps (file "mli") (file "cmti"));
    let actual = sites ~caps (file "ml") (file "cmt") in
    expect name expected actual;
    if expected <> [] then wrong_site_red name actual
  in
  check "wall" wall;
  check "unknown" unknown;
  check "clean" []

let run ~caps =
  match Array.to_list Sys.argv with
  | [ _; directory ] -> fixtures ~caps directory
  | [ _; "--clean"; source; annotation ] ->
      expect source [] (sites ~caps source annotation)
  | [ _; source; annotation ] ->
      List.iter
        (fun site -> Ox_caps.Cap_stdlib.printf ~caps "%s\n" (show site))
        (sites ~caps source annotation)
  | _ -> failwith "usage: test_monotonic_time SCRATCH | --clean SOURCE CMT | SOURCE CMT"

let () = run ~caps:(Ox_caps_door.powerbox ())
