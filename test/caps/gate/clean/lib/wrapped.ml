(* ^ncaps-n6r0 ^ncaps-4btv: the same operations through the wrappers, with the
   capability in each signature. The gate must report nothing. *)
open Ox_caps

let fork ~caps () = Cap_unix.fork ~caps ()
let exec ~caps () = Cap_unix.system ~caps "true"
let chdir ~caps () = Cap_sys.chdir ~caps "/"
let env ~caps () = Cap_sys.getenv_opt ~caps "HOME"
let stdout ~caps () = Cap_stdlib.print_endline ~caps "wrapped"
let fs_read ~caps path = Cap_stdlib.open_in_bin ~caps path
let read_line r = r
let not_stdin () = read_line 3
