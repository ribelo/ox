(* ^safe-ldtb ^safe-j6t8 ^safe-r1xw: one MI-first exact fixture and consumer corpus. *)
(* ^safe-8pmk ^safe-p1m1 ^safe-iq5u: one exact MI-first corpus and real Ox SQL disclosure witness. *)
open Ocaml_common

let scan ~caps annotation source =
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
    Transaction_runner.check ~caps ~emit:(record "finding") ~undecided:(record "unknown")
  in
  (match artifact.info.cmt_annots with
  | Interface tree -> visitor.signature visitor tree
  | Implementation tree -> visitor.structure visitor tree
  | _ -> failwith "implementation or interface evidence required");
  (Option.value ~default:source artifact.info.cmt_sourcefile, !observations)

let expected file =
  [
    ( file,
      6,
      52,
      6,
      60,
      "finding",
      "operation uses the originating pool; use the callback transaction runner" );
  ]

let fixtures ~caps clean_i clean_is bad_i bad_is clean clean_s bad bad_s =
  List.iter
    (fun (a, s) ->
      let _, rows = scan ~caps a s in
      assert (rows = []))
    [ (clean_i, clean_is); (bad_i, bad_is); (clean, clean_s) ];
  let file, rows = scan ~caps bad bad_s in
  if List.sort compare rows <> List.sort compare (expected file) then
    failwith
      ("literal observation mismatch: "
      ^ String.concat " | "
          (List.map
             (fun (file, line, first, _, last, channel, message) ->
               Printf.sprintf "%s %s:%d:%d-%d %s" channel file line first last message)
             rows))

let main
    ~(caps :
       < Ox_caps.Cap.fs_read
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.stdout
       ; .. >) () =
  match Array.to_list Sys.argv with
  | [ _; "--fixtures"; ci; cis; bi; bis; c; cs; b; bs ] ->
      fixtures ~caps ci cis bi bis c cs b bs
  | _ :: pairs ->
      let rec loop = function
        | [] -> ()
        | annotation :: source :: rest ->
            let _, rows = scan ~caps annotation source in
            List.iter
              (fun (file, line, first, _, last, channel, message) ->
                Ox_caps.Cap_stdlib.printf ~caps "%s %s:%d:%d-%d %s\n" channel file line
                  first last message)
              rows;
            loop rest
        | _ -> failwith "usage: corpus [ANNOTATION SOURCE]..."
      in
      loop pairs
  | [] -> assert false

let () = main ~caps:(Ox_test.powerbox ()) ()
