(* ^nonce-ldtz: the sole affine-to-many cast, guarded before user code. *)
let guard (f : (unit -> 'a) @ once) : unit -> 'a =
  let f = Obj.magic_many f in
  let used = Atomic.make false in
  fun () ->
    if Atomic.exchange used true then invalid_arg "Ox.Once.guard: callback already used"
    else f ()
