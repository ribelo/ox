(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

let violation () = Stdlib.read_line ()

(* ^ncapslint-t4c6: raw standard descriptors, including redirection destinations. *)
let descriptor () = Unix.stdin
let redirect source = Unix.dup2 source Unix.stdin
