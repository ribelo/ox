(* ^safe-28t6: observable write must disappear in the broken release consumer. *)
let () =
  let cell = ref 0 in
  assert (
    Stdlib.incr cell;
    true);
  Stdlib.print_int !cell;
  Stdlib.print_newline ()
