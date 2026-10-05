(* ^safe-pcom ^safe-u7cx: exact pinned load versus update, not a synchronization-wide purity claim. *)
module A = Stdlib.Atomic

let read cell =
  assert (Stdlib.Atomic.get cell = 2);
  assert (A.get cell = 2)

let write cell =
  assert (
    Stdlib.Atomic.set cell 2;
    true);
  assert (A.exchange cell 3 = 2);
  assert (Stdlib.Atomic.fetch_and_add cell 1 = 3)

let callback cell = assert ((Stdlib.Atomic.get cell) ())
