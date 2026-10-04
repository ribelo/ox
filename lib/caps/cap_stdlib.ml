let exit ~caps:(_caps : < Cap.exit ; .. >) code = Stdlib.exit code
let stdin ~caps:(_caps : < Cap.stdin ; .. >) = Stdlib.stdin
let read_line ~caps:(_caps : < Cap.stdin ; .. >) () = Stdlib.read_line ()
let stdout ~caps:(_caps : < Cap.stdout ; .. >) = Stdlib.stdout
let std_formatter ~caps:(_caps : < Cap.stdout ; .. >) = Format.std_formatter
let print_string ~caps:(_caps : < Cap.stdout ; .. >) s = Stdlib.print_string s
let print_bytes ~caps:(_caps : < Cap.stdout ; .. >) b = Stdlib.print_bytes b
let print_char ~caps:(_caps : < Cap.stdout ; .. >) c = Stdlib.print_char c
let print_int ~caps:(_caps : < Cap.stdout ; .. >) n = Stdlib.print_int n
let print_float ~caps:(_caps : < Cap.stdout ; .. >) x = Stdlib.print_float x
let print_endline ~caps:(_caps : < Cap.stdout ; .. >) s = Stdlib.print_endline s
let print_newline ~caps:(_caps : < Cap.stdout ; .. >) () = Stdlib.print_newline ()
let printf ~caps:(_caps : < Cap.stdout ; .. >) format = Printf.printf format
let stderr ~caps:(_caps : < Cap.stderr ; .. >) = Stdlib.stderr
let err_formatter ~caps:(_caps : < Cap.stderr ; .. >) = Format.err_formatter
let prerr_string ~caps:(_caps : < Cap.stderr ; .. >) s = Stdlib.prerr_string s
let prerr_bytes ~caps:(_caps : < Cap.stderr ; .. >) b = Stdlib.prerr_bytes b
let prerr_char ~caps:(_caps : < Cap.stderr ; .. >) c = Stdlib.prerr_char c
let prerr_int ~caps:(_caps : < Cap.stderr ; .. >) n = Stdlib.prerr_int n
let prerr_float ~caps:(_caps : < Cap.stderr ; .. >) x = Stdlib.prerr_float x
let prerr_endline ~caps:(_caps : < Cap.stderr ; .. >) s = Stdlib.prerr_endline s
let prerr_newline ~caps:(_caps : < Cap.stderr ; .. >) () = Stdlib.prerr_newline ()
let eprintf ~caps:(_caps : < Cap.stderr ; .. >) format = Printf.eprintf format
let open_in ~caps:(_caps : < Cap.fs_read ; .. >) path = Stdlib.open_in path
let open_in_bin ~caps:(_caps : < Cap.fs_read ; .. >) path = Stdlib.open_in_bin path

let open_in_gen ~caps:(_caps : < Cap.fs_read ; .. >) flags perm path =
  Stdlib.open_in_gen flags perm path

let open_out ~caps:(_caps : < Cap.fs_write ; .. >) path = Stdlib.open_out path
let open_out_bin ~caps:(_caps : < Cap.fs_write ; .. >) path = Stdlib.open_out_bin path

let open_out_gen ~caps:(_caps : < Cap.fs_write ; .. >) flags perm path =
  Stdlib.open_out_gen flags perm path

module In_channel = struct
  let open_bin ~caps:(_caps : < Cap.fs_read ; .. >) path = In_channel.open_bin path
  let open_text ~caps:(_caps : < Cap.fs_read ; .. >) path = In_channel.open_text path

  let with_open_bin ~caps:(_caps : < Cap.fs_read ; .. >) path f =
    In_channel.with_open_bin path f

  let with_open_text ~caps:(_caps : < Cap.fs_read ; .. >) path f =
    In_channel.with_open_text path f

  let with_open_gen ~caps:(_caps : < Cap.fs_read ; .. >) flags perm path f =
    In_channel.with_open_gen flags perm path f
end

module Out_channel = struct
  let open_bin ~caps:(_caps : < Cap.fs_write ; .. >) path = Out_channel.open_bin path
  let open_text ~caps:(_caps : < Cap.fs_write ; .. >) path = Out_channel.open_text path

  let open_gen ~caps:(_caps : < Cap.fs_write ; .. >) flags perm path =
    Out_channel.open_gen flags perm path

  let with_open_bin ~caps:(_caps : < Cap.fs_write ; .. >) path f =
    Out_channel.with_open_bin path f

  let with_open_text ~caps:(_caps : < Cap.fs_write ; .. >) path f =
    Out_channel.with_open_text path f

  let with_open_gen ~caps:(_caps : < Cap.fs_write ; .. >) flags perm path f =
    Out_channel.with_open_gen flags perm path f
end

module Random = struct
  let self_init ~caps:(_caps : < Cap.random ; .. >) () = Random.self_init ()

  let make_self_init ~caps:(_caps : < Cap.random ; .. >) () =
    Random.State.make_self_init ()
end

module Filename = struct
  let temp_file ~caps:(_caps : < Cap.tmp ; .. >) ?temp_dir prefix suffix =
    Filename.temp_file ?temp_dir prefix suffix

  let open_temp_file ~caps:(_caps : < Cap.tmp ; .. >) ?mode ?perms ?temp_dir prefix suffix
      =
    Filename.open_temp_file ?mode ?perms ?temp_dir prefix suffix

  let temp_dir ~caps:(_caps : < Cap.tmp ; .. >) ?temp_dir ?perms prefix suffix =
    Filename.temp_dir ?temp_dir ?perms prefix suffix
end
