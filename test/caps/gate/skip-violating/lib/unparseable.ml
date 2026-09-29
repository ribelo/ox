(* ^ncaps-a27b ^ncaps-tpjy ^ncaps-rwnz: a forbidden call in an OxCaml parse gap. *)
let borrow (value @ local) = Unix.fork ()
