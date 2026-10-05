(* ^safe-pcom ^safe-u7cx: actual evaluation, including captured arguments and function cases. *)
let cases cell = function
  | () ->
      Stdlib.incr cell;
      true

let check cell =
  assert (cases cell ());
  assert (
    let _partial =
      Stdlib.Array.set
        (Stdlib.incr cell;
         [| 0 |])
    in
    true);
  let partial =
    Stdlib.Array.set
      (Stdlib.incr cell;
       [| 0 |])
  in
  assert (
    partial 0 1;
    true);
  let staged cell =
    Stdlib.incr cell;
    fun () -> true
  in
  assert (
    let _closure = staged cell in
    true)

let nested cell =
  assert (
    assert (
      Stdlib.incr cell;
      true);
    true)
