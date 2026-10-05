(* ^safe-9gfb ^safe-tlyw: use fresh compiler evidence before the public source decider. *)
open Ocaml_common

let check ~caps directory extension expected =
  let source = directory ^ "/identity_external." ^ extension in
  let annotation =
    Printf.sprintf
      "%s/.identity_external_%s.objs/byte/identity_external_%s__Identity_external.%s"
      directory directory directory
      (if extension = "ml" then "cmt" else "cmti")
  in
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let sites = ref [] in
  Syntax.walk ~caps source
    (Identity_external.source (fun loc ->
         sites := loc.Location.loc_start.Lexing.pos_lnum :: !sites));
  let actual = List.sort Int.compare !sites in
  if actual <> expected then
    failwith
      (Printf.sprintf "%s: expected [%s], got [%s]" source
         (String.concat ";" (List.map string_of_int expected))
         (String.concat ";" (List.map string_of_int actual)))

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read >) in
  check ~caps "negative" "ml" [ 2; 3; 6; 14; 18; 22 ];
  check ~caps "negative" "mli" [ 2; 3; 6; 14; 18; 22 ];
  check ~caps "positive" "ml" [];
  check ~caps "positive" "mli" []
