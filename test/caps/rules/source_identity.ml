(* ^ncapslint-w2tq: source identity must respect every binder shape. *)
let read_line x = x
let stdin = "local"
let a = read_line stdin
let b = Stdlib.read_line ()
let exit _ = ()
let c = exit 0
module U = Unix
let d = U.fork ()
let e = let open U in fork ()
let f = let module Unix = struct let fork () = 0 end in Unix.fork ()
module Local = struct let fork () = 0 end
open Local
let g = fork ()
let h = let open Unix in fork ()
module S = struct let stdout = "local" end
open S
let i = stdout
let j = Stdlib.stdout
let k ~(stdout : string) = stdout
type record = { stdout : string }
let l r = r.stdout
let m = let rec fork x = fork x in fork 0
let n x = match x with Some exit -> exit 0 | None -> ()
module Shadow_stdlib = struct let exit _ = () end
module Stdlib = Shadow_stdlib
let o = Stdlib.exit 0
