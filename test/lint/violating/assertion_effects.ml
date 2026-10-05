(* ^safe-pcom: required mutation is wrongly removable. *)
let check cell = assert (Stdlib.incr cell; true)
