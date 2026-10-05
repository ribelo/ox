(* ^nonce-mjpe ^nonce-nngp: native unique captures in both branches. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff sw (x : owned @ unique) (y : owned @ unique) =
 Ox.Concurrent.both ~sw (fun () -> ignore (consume x); Ok ()) (fun () -> ignore (consume y); Ok ())
