(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

let violation () = Stdlib.prerr_endline "x"

(* ^ncapslint-t4c6: raw standard descriptors, including redirection destinations. *)
let descriptor () = Unix.stderr
let redirect source = Unix.dup2 source Unix.stderr
