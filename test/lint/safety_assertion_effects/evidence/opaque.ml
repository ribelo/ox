(* ^safe-u7cx: actual native declaration and opaque parameter, not pure by name. *)
external read : int -> int = "%identity"

let check predicate =
  assert (predicate ());
  assert (
    let _value = read 1 in
    true)
