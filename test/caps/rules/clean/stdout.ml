(* ^ncapslint-nf4t: an ordinary local binding is not a standard-library origin. *)
let exit x = x
let fork () = 0
let stdout = "local"
let value () = (exit (fork ()), stdout)

(* ^ncapslint-t4c6: lookalike constants are not process-standard descriptors. *)
module Unix = struct
  let stdout = 0
  let dup2 _ destination = destination
end

let descriptor () = Unix.stdout
let redirect source = Unix.dup2 source Unix.stdout
