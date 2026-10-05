(* ^safe-1kqm ^safe-gm8y ^safe-y047: standalone actual-provider evidence audit. *)
let run ~(caps : < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stderr ; Ox_caps.Cap.exit >) =
  match Array.to_list Sys.argv with
  | [ _; source; annotation ] ->
      let artifact = Artifact.read ~caps annotation in
      Artifact.check ~caps ~source artifact;
      Artifact.setup ~caps artifact;
      let rejected = ref false in
      let report kind loc message =
        rejected := true;
        Ox_caps.Cap_stdlib.eprintf ~caps "%s:%d: %s: %s\n"
          loc.Ocaml_common.Location.loc_start.Lexing.pos_fname loc.loc_start.pos_lnum kind
          message
      in
      Codec_seams.check ~caps artifact ~emit:(report "finding")
        ~undecided:(report "undecided");
      if !rejected then Ox_caps.Cap_stdlib.exit ~caps 1
  | _ -> failwith "usage: audit SOURCE ANNOTATION"

let () =
  run
    ~caps:
      (Ox_test.powerbox ()
        :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stderr ; Ox_caps.Cap.exit >)
