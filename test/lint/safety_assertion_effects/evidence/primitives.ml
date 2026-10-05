(* ^safe-u7cx: pinned scalar/ref primitives; native reads remain outside horizon. *)
let clean cell =
  assert (
    ignore ();
    not false);
  assert (!cell = 1);
  assert (
    let _fresh = ref 0 in
    1 + 2 = 3)

let outside values = assert (Stdlib.Array.get values 0 = 1)
let custom value = assert (value = value)
