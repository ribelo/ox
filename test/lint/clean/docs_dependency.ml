(* ^nlintd-truth: cross-compilation-unit effect leaf. *)
let noop _ = ()
let check = Eio.Switch.check

(* ^nlintd-k036: a known sibling retains its own opaque delegated boundary. *)
let unknown_raise _ = ignore (Format.asprintf "%d" 1)
