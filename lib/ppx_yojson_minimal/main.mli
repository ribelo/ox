(** Entry point of the [ppx-yojson-minimal] preprocessor binary: [main.exe file] prints
    the preprocessed source. The executable declares [ox_caps.door] and mints once at
    entry. Its main function receives [Cap.exit], [Cap.fs_read], [Cap.stdout] and
    [Cap.stderr], narrowing away [Cap.exit] before running the transformation. The
    capability dependencies are confined to this executable, not the deriver library or
    the generated converters. *)
