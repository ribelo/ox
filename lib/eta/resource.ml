let acquire_release ~sw ~acquire ~release =
  match acquire () with
  | Error _ as error -> error
  | Ok resource ->
      Eio.Switch.on_release sw (fun () -> release resource);
      Ok resource
