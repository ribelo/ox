(* ^safe-sr6e ^safe-9hbm ^safe-eftp: literal sites retain origin and multiplicity. *)
open Ocaml_common

let check ~caps ~source ~annotation =
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let observations = ref [] in
  let record channel loc message =
    let a = loc.Location.loc_start and b = loc.loc_end in
    observations :=
      ( a.Lexing.pos_fname,
        a.pos_lnum,
        a.pos_cnum - a.pos_bol,
        b.pos_lnum,
        b.pos_cnum - b.pos_bol,
        channel,
        message )
      :: !observations
  in
  let visitor =
    Execution_context.check ~caps ~emit:(record "finding") ~undecided:(record "unknown")
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> visitor.structure visitor tree
  | _ -> failwith "native implementation required");
  let file = Filename.basename source in
  let site channel line first last origin reason =
    ( file,
      line,
      first,
      line,
      last,
      channel,
      Printf.sprintf "Ox_blocking.run native callback at %s:%d: %s" file origin reason )
  in
  let expected =
    match file with
    | "boundary_pairs.ml" ->
        [
          site "unknown" 2 53 59 2
            "unresolved optional default containing known Eio candidate";
          site "finding" 3 44 59 7 "Eio.Fiber.yield requires an Eio fiber context";
          site "unknown" 16 35 41 16
            "unresolved optional default containing known Eio candidate";
          site "unknown" 13 46 47 12
            "unresolved known Eio value escaping opaque call or scope";
        ]
    | "catalogue_pairs.ml" ->
        [
          site "finding" 5 18 29 6 "Eio.Fiber.yield requires an Eio fiber context";
          site "finding" 7 15 16 8 "Eio.Fiber.yield requires an Eio fiber context";
          site "unknown" 17 53 59 17
            "unresolved known Eio value escaping opaque call or scope";
        ]
    | _ -> failwith "unexpected paired consumer"
  in
  if List.sort compare expected <> List.sort compare !observations then
    failwith
      ("literal native candidate observations mismatch: "
      ^ String.concat " | "
          (List.map
             (fun (file, line, first, _, last, channel, message) ->
               Printf.sprintf "%s %s:%d:%d-%d %s" channel file line first last message)
             !observations))

let () =
  let caps = Ox_test.powerbox () in
  match Array.to_list Sys.argv with
  | [ _; annotation; source ] -> check ~caps ~source ~annotation
  | _ -> failwith "usage: test_worker_context ANNOTATION SOURCE"
