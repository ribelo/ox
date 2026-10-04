(* ^ncapslint-nf4t: an ordinary local binding is not a standard-library origin. *)
let exit x = x
let fork () = 0
let stdout = "local"
let value () = (exit (fork ()), stdout)
