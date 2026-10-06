(* ^safe-9ved ^safe-ohen: report checked library evidence, never unknown-as-clean. *)
open Ocaml_common

let findings = ref 0
and unknowns = ref 0

let decided = ref 0
and undecided = ref 0

let production_findings = ref 0
and test_findings = ref 0

let scan
    ~(caps :
       < Ox_caps.Cap.fs_read
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.stdout
       ; .. >) source annotation =
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let report ~(caps : < Ox_caps.Cap.stdout ; .. >) certainty loc message =
    if certainty = "finding" then (
      incr findings;
      if
        List.exists
          (fun part -> part = "test" || part = "tests")
          (String.split_on_char '/' source)
      then incr test_findings
      else incr production_findings)
    else incr unknowns;
    let first = loc.Location.loc_start and last = loc.Location.loc_end in
    Ox_caps.Cap_stdlib.printf ~caps "%s %s:%d:%d-%d:%d %s\n" certainty source
      first.Lexing.pos_lnum
      (first.pos_cnum - first.pos_bol)
      last.pos_lnum
      (last.pos_cnum - last.pos_bol)
      message
  in
  let iterator =
    Fiber_blocking.check ~caps ~emit:(report ~caps "finding")
      ~undecided:(report ~caps "undecided")
  in
  match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | _ -> failwith ("implementation evidence required: " ^ source)

let main
    ~(caps :
       < Ox_caps.Cap.fs_read
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.stdout
       ; .. >) () =
  let arguments = Array.length Sys.argv - 1 in
  if arguments = 0 || arguments mod 2 <> 0 then
    failwith "actual source/annotation pairs from the declared inventory are required";
  for index = 0 to (arguments / 2) - 1 do
    let before = !unknowns in
    scan ~caps Sys.argv.(1 + (2 * index)) Sys.argv.(2 + (2 * index));
    if !unknowns = before then incr decided else incr undecided
  done;
  Ox_caps.Cap_stdlib.print_endline ~caps
    (Printf.sprintf "inventory: %d implementations, %d findings, %d required unknowns"
       (arguments / 2) !findings !unknowns);
  Ox_caps.Cap_stdlib.print_endline ~caps
    (Printf.sprintf "files: %d decided, %d undecided; findings: %d production, %d test"
       !decided !undecided !production_findings !test_findings)

let () = main ~caps:(Ox_test.powerbox ()) ()
