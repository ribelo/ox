(* Tests are outside the gate: this raw call must not be reported. *)
let fork () = Unix.fork ()
