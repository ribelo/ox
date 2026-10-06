(* ^safe-sx2y ^safe-5ajg ^safe-88rt ^safe-qczi *)
open Ocaml_common

let scan ~caps annotation source =
  let artifact =
    if annotation = "auto" then Artifact.find ~caps source
    else Artifact.read ~caps annotation
  in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let rows = ref [] in
  let record channel loc message =
    let p = loc.Location.loc_start in
    rows :=
      ( channel,
        p.Lexing.pos_lnum,
        p.pos_cnum - p.pos_bol,
        loc.loc_end.pos_cnum - loc.loc_end.pos_bol,
        message )
      :: !rows
  in
  let visitor =
    Unbounded_read.check ~caps ~emit:(record "finding") ~undecided:(record "unknown")
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> visitor.structure visitor tree
  | Interface tree -> visitor.signature visitor tree
  | _ -> failwith "partial evidence");
  List.rev !rows

let main ~caps () =
  match Array.to_list Sys.argv with
  | [ _; "--fixtures"; ci; cs; bi; bs ] ->
      let clean = scan ~caps ci cs and bad = scan ~caps bi bs in
      if clean <> [] then failwith "bounded/alias/shadow controls changed";
      let locations = List.map (fun (channel, line, _, _, _) -> (channel, line)) bad in
      if locations <> [ ("finding", 2); ("finding", 3); ("finding", 4); ("finding", 7) ]
      then (
        List.iter
          (fun (c, l, a, b, m) ->
            Ox_caps.Cap_stdlib.eprintf ~caps "%s:%d:%d-%d %s\n" c l a b m)
          bad;
        failwith "exact unbounded-read fixture findings changed")
  | _ :: pairs ->
      let rec loop = function
        | [] -> ()
        | annotation :: source :: rest ->
            (try
               List.iter
                 (fun (c, l, a, b, m) ->
                   Ox_caps.Cap_stdlib.printf ~caps "%s\t%s\t%d\t%d\t%d\t%s\n" c source l a
                     b m)
                 (scan ~caps annotation source);
               Ox_caps.Cap_stdlib.printf ~caps "decided\t%s\n" source
             with ex ->
               Ox_caps.Cap_stdlib.printf ~caps "file_unknown\t%s\t%s\n" source
                 (Printexc.to_string ex));
            loop rest
        | _ -> failwith "annotation/source pairs required"
      in
      loop pairs
  | [] -> assert false

let () = main ~caps:(Ox_test.powerbox ()) ()
