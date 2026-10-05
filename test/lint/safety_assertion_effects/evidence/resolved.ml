(* ^safe-pcom: fully resolved standard calls, including a module alias. *)
module S = Stdlib

let check cell =
  assert (
    Stdlib.incr cell;
    true);
  assert (
    S.print_endline "required output";
    true);
  assert (
    Stdlib.Array.set [| 0 |] 0 1;
    true)

let dormant cell =
  assert (
    let _closure = fun () -> Stdlib.incr cell in
    true);
  assert (
    let _partial = Stdlib.Array.set [| 0 |] in
    true);
  assert (
    let _lazy = lazy (Stdlib.incr cell) in
    true)

let pure () =
  assert (
    ();
    true)
