(* ^safe-pcom: this write disappears with -noassert. *)
type cell = { mutable value : int }

let check cell =
  assert (
    cell.value <- 1;
    true)
