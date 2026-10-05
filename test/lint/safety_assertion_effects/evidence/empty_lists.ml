(* ^safe-u7cx: exact built-in empty-list comparison cannot inspect element payloads.
   Operand evaluation, functional payload comparison and custom types stay separate. *)
let clean (callbacks : (unit -> unit) list) =
  assert (callbacks = []);
  assert ([] <> callbacks);
  assert (callbacks < []);
  assert ([] > callbacks);
  assert (callbacks <= []);
  assert ([] >= callbacks);
  let equal = Stdlib.( = ) in
  assert (equal callbacks [])

let effectful cell =
  assert ((Stdlib.incr cell; [fun () -> ()]) <> [])

let opaque (obtain : unit -> (unit -> unit) list) =
  assert (obtain () = [])

let functional (left : (unit -> unit) list) right =
  assert (left = right)

let nonempty () =
  assert ([fun () -> ()] = [fun () -> ()])

let custom
    (left : (int, Bigarray.int_elt, Bigarray.c_layout) Bigarray.Array1.t)
    right =
  assert (left = right)

(* Built-in spelling alone cannot admit a different type's constructors. *)
type counterfeit = [] | ( :: ) of (unit -> unit) * counterfeit
let counterfeit value = assert (value = ([] : counterfeit))
