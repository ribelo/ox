(* ^safe-u7cx ^safe-28t6: required work and validation are ordinary code. *)
let check cell =
  Stdlib.incr cell;
  if !cell = 1 then Ok () else Error `Unexpected_value

let invariant () =
  assert (
    ();
    true)
