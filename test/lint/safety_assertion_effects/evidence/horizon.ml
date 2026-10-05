(* ^safe-u7cx: optional defaults and dereferenced callbacks are not declared pure. *)
let optional cell =
  let predicate
      ?(value =
        Stdlib.incr cell;
        true) () =
    value
  in
  assert (predicate ())

let callback cell = assert (!cell ())

let captured cell =
  let predicate = !cell in
  assert (predicate ())

module Stdlib = struct
  let incr _ = ()
end

let module_shadow cell =
  assert (
    Stdlib.incr cell;
    true)
