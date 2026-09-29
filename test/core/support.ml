(* Test sugar over [Eio.Switch.on_release]: Eta has no resource module (nsup-gxmx); the
   ported v1 cases acquire a value and register its release in one step. *)
let acquire_release ~sw ~acquire ~release =
  match acquire () with
  | Error _ as error -> error
  | Ok resource ->
      Eio.Switch.on_release sw (fun () -> release resource);
      Ok resource
