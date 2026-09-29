let exit ~caps:_ code = Stdlib.exit code
let stdin ~caps:_ = Stdlib.stdin
let read_line ~caps:_ () = Stdlib.read_line ()
let stdout ~caps:_ = Stdlib.stdout
let std_formatter ~caps:_ = Format.std_formatter
let print_string ~caps:_ s = Stdlib.print_string s
let print_bytes ~caps:_ b = Stdlib.print_bytes b
let print_char ~caps:_ c = Stdlib.print_char c
let print_int ~caps:_ n = Stdlib.print_int n
let print_float ~caps:_ x = Stdlib.print_float x
let print_endline ~caps:_ s = Stdlib.print_endline s
let print_newline ~caps:_ () = Stdlib.print_newline ()
let printf ~caps:_ format = Printf.printf format
let stderr ~caps:_ = Stdlib.stderr
let err_formatter ~caps:_ = Format.err_formatter
let prerr_string ~caps:_ s = Stdlib.prerr_string s
let prerr_bytes ~caps:_ b = Stdlib.prerr_bytes b
let prerr_char ~caps:_ c = Stdlib.prerr_char c
let prerr_int ~caps:_ n = Stdlib.prerr_int n
let prerr_float ~caps:_ x = Stdlib.prerr_float x
let prerr_endline ~caps:_ s = Stdlib.prerr_endline s
let prerr_newline ~caps:_ () = Stdlib.prerr_newline ()
let eprintf ~caps:_ format = Printf.eprintf format
let open_in ~caps:_ path = Stdlib.open_in path
let open_in_bin ~caps:_ path = Stdlib.open_in_bin path
let open_in_gen ~caps:_ flags perm path = Stdlib.open_in_gen flags perm path
let open_out ~caps:_ path = Stdlib.open_out path
let open_out_bin ~caps:_ path = Stdlib.open_out_bin path
let open_out_gen ~caps:_ flags perm path = Stdlib.open_out_gen flags perm path

module In_channel = struct
  let open_bin ~caps:_ path = In_channel.open_bin path
  let open_text ~caps:_ path = In_channel.open_text path
  let with_open_bin ~caps:_ path f = In_channel.with_open_bin path f
  let with_open_text ~caps:_ path f = In_channel.with_open_text path f
  let with_open_gen ~caps:_ flags perm path f = In_channel.with_open_gen flags perm path f
end

module Out_channel = struct
  let open_bin ~caps:_ path = Out_channel.open_bin path
  let open_text ~caps:_ path = Out_channel.open_text path
  let open_gen ~caps:_ flags perm path = Out_channel.open_gen flags perm path
  let with_open_bin ~caps:_ path f = Out_channel.with_open_bin path f
  let with_open_text ~caps:_ path f = Out_channel.with_open_text path f

  let with_open_gen ~caps:_ flags perm path f =
    Out_channel.with_open_gen flags perm path f
end

module Random = struct
  let self_init ~caps:_ () = Random.self_init ()
  let make_self_init ~caps:_ () = Random.State.make_self_init ()
end

module Filename = struct
  let temp_file ~caps:_ ?temp_dir prefix suffix =
    Filename.temp_file ?temp_dir prefix suffix

  let open_temp_file ~caps:_ ?mode ?perms ?temp_dir prefix suffix =
    Filename.open_temp_file ?mode ?perms ?temp_dir prefix suffix

  let temp_dir ~caps:_ ?temp_dir ?perms prefix suffix =
    Filename.temp_dir ?temp_dir ?perms prefix suffix
end
