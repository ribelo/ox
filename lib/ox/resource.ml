let use_in_scope ~sw (acquire @ local) release =
  let resource = acquire () in
  (* ^nfloor-once: Eio runs release itself before rejecting a finished switch. *)
  Eio.Switch.on_release sw (fun () -> release resource);
  resource

let use_closeable_in_scope ~sw (acquire @ local) =
  use_in_scope ~sw acquire Eio.Resource.close
