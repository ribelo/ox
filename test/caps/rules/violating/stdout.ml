(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

let violation () = Stdlib.print_endline "x"

(* ^ncapslint-t4c6: raw standard descriptors, including redirection destinations. *)
let descriptor () = Unix.stdout
let redirect source = Unix.dup2 source Unix.stdout
