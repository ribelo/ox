let use_in_scope ~sw (acquire @ local) release =
  let resource = acquire () in
  (match Eio.Switch.on_release sw (fun () -> release resource) with
  | () -> ()
  | exception exn ->
      let backtrace = Printexc.get_raw_backtrace () in
      release resource;
      Printexc.raise_with_backtrace exn backtrace);
  resource

let use_closeable_in_scope ~sw (acquire @ local) =
  use_in_scope ~sw acquire Eio.Resource.close
