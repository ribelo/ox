(** See [Main.mli]. Thin input/output wrapper around [Expand.process]: exit 0 with the
    preprocessed file on stdout, exit 2 with the reason on stderr. *)

open Ox_caps

let read_file ~(caps : < Cap.fs_read ; .. >) path =
  Cap_stdlib.In_channel.with_open_bin ~caps path (fun channel ->
      let length = in_channel_length channel in
      really_input_string channel length)

let run ~(caps : < Cap.fs_read ; Cap.stdout ; Cap.stderr ; .. >) argv =
  match argv with
  | [| _; path |] -> (
      match read_file ~caps path with
      | exception Sys_error message ->
          Cap_stdlib.eprintf ~caps "ppx-ox-let: %s\n" message;
          2
      | source -> (
          match Ppx_ox_let.Expand.process ~filename:path ~source with
          | Ok output ->
              Cap_stdlib.print_string ~caps output;
              0
          | Error message ->
              Cap_stdlib.eprintf ~caps "%s\n" message;
              2))
  | _ ->
      Cap_stdlib.eprintf ~caps "usage: ppx-ox-let <file.ml|file.mli>\n";
      2

let main ~(caps : < Cap.exit ; Cap.fs_read ; Cap.stdout ; Cap.stderr ; .. >) argv =
  Cap_stdlib.exit ~caps
    (run ~caps:(caps :> < Cap.fs_read ; Cap.stdout ; Cap.stderr >) argv)

let () =
  let caps = Ox_caps_door.powerbox () in
  main ~caps:(caps :> < Cap.exit ; Cap.fs_read ; Cap.stdout ; Cap.stderr >) Sys.argv
