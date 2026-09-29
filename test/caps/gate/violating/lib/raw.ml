(* ^ncaps-n6r0: one raw call per rule of caps.yaml. The gate must report every rule
   here; this file is a fixture, never compiled. *)
let fork () = Unix.fork ()
let exec () = Unix.system "true"
let leave () = exit 3
let chdir () = Sys.chdir "/"
let env () = Sys.getenv_opt "HOME"
let signal pid = Unix.kill pid Sys.sigterm
let time () = Unix.gettimeofday ()
let random () = Random.self_init ()
let stdin () = read_line ()
let stdout () = print_endline "raw"
let stderr () = Printf.eprintf "raw\n"
let fs_read path = open_in_bin path
let fs_write path = Out_channel.with_open_bin path (fun _ -> ())
let tmp () = Filename.temp_file "raw" ".tmp"
let network () = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0
let mint () = Ox_caps.Cap.powerbox ()
let forge () : Ox_caps.Cap.exec = Obj.magic ()

(* An inline suppression does not work: the gate runs with --disable-nosem. *)
let hidden () = Unix.fork () (* nosemgrep *)
