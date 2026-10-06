(* ^safe-ctc4 ^safe-vj9b ^safe-tcqo: one exact MI-first consumer corpus and physical defect witness. *)
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
    Cancel_mask.check ~caps ~emit:(record "finding") ~undecided:(record "unknown")
  in
  (match artifact.info.cmt_annots with
  | Interface tree -> visitor.signature visitor tree
  | Implementation tree -> visitor.structure visitor tree
  | _ -> failwith "implementation or interface evidence required");
  (Option.value ~default:source artifact.info.cmt_sourcefile, !observations)

let expected file =
  let wait =
    "known indefinite server/cancellation wait executes inside cancellation protection; \
     reduce mask scope or use an inner finite deadline"
  in
  let server =
    "known indefinite server wait executes inside cancellation protection; reduce mask \
     scope or change the interface"
  in
  List.map
    (fun (line, first, last) ->
      (file, line, first, line, last, "finding", if line = 10 then server else wait))
    [
      (2, 46, 71);
      (5, 21, 28);
      (7, 16, 41);
      (10, 32, 90);
      (12, 49, 74);
      (14, 38, 63);
      (18, 50, 75);
      (20, 41, 63);
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

let witness ~caps:_ () =
  Eio_main.run (fun env ->
      match
        Eio.Time.with_timeout (Eio.Stdenv.clock env) 0.001 (fun () ->
            Eio.Cancel.protect Eio.Fiber.await_cancel)
      with
      | Ok _ | Error _ ->
          failwith "outer cancellation incorrectly settled the protected indefinite wait")

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
  | [ _; "--witness" ] -> witness ~caps ()
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
