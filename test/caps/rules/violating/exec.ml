(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

let violation () = Unix.system "true"
