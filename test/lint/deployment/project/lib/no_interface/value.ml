(* ^nlintcov-q6n2: a real package module without an interface. *)
let result () : (unit, string) result = Ok ()
let run () = ignore (result ())
