(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

let violation () = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0
