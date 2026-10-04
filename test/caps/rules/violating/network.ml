(* ^ncapslint-nf4t ^ncapslint-w2tq: never run, compiled rule evidence. *)
let violation () = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0
