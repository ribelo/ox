(** See [Main.mli]. Thin input/output wrapper around [Derive.process]: exit 0 with the
    preprocessed source on stdout, exit 2 with the reason on stderr when derivation was
    requested but is not supported. *)

let read_file path =
  let channel = open_in_bin path in
  let length = in_channel_length channel in
  let source = really_input_string channel length in
  close_in channel;
  source

let () =
  match Sys.argv with
  | [| _; path |] -> (
      let source =
        match read_file path with
        | text -> text
        | exception Sys_error message ->
            Printf.eprintf "ppx-yojson-minimal: %s\n" message;
            exit 2
      in
      match Ppx_yojson_minimal.Derive.process ~filename:path ~source with
      | Ok output -> print_string output
      | Error message ->
          Printf.eprintf "ppx-yojson-minimal: %s\n" message;
          exit 2)
  | _ ->
      Printf.eprintf "usage: ppx-yojson-minimal <file.ml|file.mli>\n";
      exit 2
