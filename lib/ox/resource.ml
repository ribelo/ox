(* ^nonce-4jzx ^nonce-lrzq: acquire is in-place; release is retained. *)
let use_in_scope ~sw (acquire @ local once) (release @ once) =
  let resource = acquire () in
  (* ^nfloor-once: Eio runs release itself before rejecting a finished switch. *)
  Eio.Switch.on_release sw (Once.guard (fun () -> release resource));
  resource

let use_closeable_in_scope ~sw (acquire @ local once) =
  use_in_scope ~sw acquire Eio.Resource.close
