(* ^safe-gm8y ^safe-y047: mutate copied real CMTs, never provider installations. *)
open Ocaml_common

let run ~(caps : < Ox_caps.Cap.fs_read ; Ox_caps.Cap.fs_write >) =
  match Array.to_list Sys.argv with
  | [ _; mode; original; destination ] ->
      ignore caps#fs_read;
      let info = Cmt_format.read_cmt original in
      let info =
        match mode with
        | "source" ->
            {
              info with
              cmt_source_digest = Some (Digest.string "unaudited emitted body");
            }
        | "pipeline" ->
            {
              info with
              cmt_args = Array.append info.cmt_args [| "-ppx"; "unknown-transform" |];
            }
        | "self" ->
            {
              info with
              cmt_imports =
                Array.of_list
                  (List.filter
                     (fun imported ->
                       Compilation_unit.Name.to_string (Import_info.name imported)
                       <> Compilation_unit.name_as_string info.cmt_modname)
                     (Array.to_list info.cmt_imports));
            }
        | _ -> failwith "unknown fault"
      in
      let channel = Ox_caps.Cap_stdlib.open_out_bin ~caps destination in
      Fun.protect
        ~finally:(fun () -> close_out channel)
        (fun () ->
          output_string channel Config.cmt_magic_number;
          Marshal.to_channel channel info [])
  | _ -> failwith "usage: fault source|pipeline|self ORIGINAL DESTINATION"

let () = run ~caps:(Ox_test.powerbox () :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.fs_write >)
