(* ^safe-pcom ^safe-u7cx: lexical stamps, aliasing and evaluated closures. *)
let mutate cell () =
  Stdlib.incr cell;
  true

let check cell =
  assert (mutate cell ());
  let alias = mutate in
  assert (alias cell ());
  assert (
    (fun () ->
      Stdlib.incr cell;
      true)
      ());
  let mutate _ () = true in
  assert (mutate cell ());
  let partial = Stdlib.Array.set [| 0 |] in
  assert (
    partial 0 1;
    true)

let shadow () =
  let print_endline _ = true in
  assert (print_endline "not stdout")

let recursion () =
  let rec loop () = loop () in
  assert (loop ())
