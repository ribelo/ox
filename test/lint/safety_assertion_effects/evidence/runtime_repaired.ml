(* ^safe-28t6: work and ordinary failure survive -noassert. *)
let () =
  let cell = ref 0 in
  Stdlib.incr cell;
  let valid = if Array.length Sys.argv > 1 then false else !cell = 1 in
  Stdlib.print_int !cell;
  Stdlib.print_newline ();
  if valid then () else Stdlib.exit 7
