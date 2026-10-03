let () = Eio_main.run (fun _ ->
  let inside = Eio_view.with_ (fun cancel ->
    Eio_view.cancel cancel;
    assert (Eio_view.receive ~cancel (Channel_base.create ()) = Error `Canceled);
    try Eio.Fiber.check (); false with Eio.Cancel.Cancelled _ -> true) in
  assert inside;
  Eio.Fiber.check ();
  print_endline "PASS pure Eio view returns Canceled but ambient context stays canceled until exit";
  Eio.Cancel.sub (fun parent ->
    let reason = Failure "parent terminated" in
    let masked = Eio_view.with_ (fun cancel ->
      Eio_view.cancel cancel;
      Eio.Cancel.cancel parent reason;
      Eio_view.receive ~cancel (Channel_base.create ()) = Error `Canceled) in
    assert masked;
    assert (try Eio.Cancel.check parent; false with Eio.Cancel.Cancelled ex -> ex == reason));
  print_endline "PASS naive pure view masks later parent cancellation unless checked after scope exit")
