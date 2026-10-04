(* ^nlintc-kdcl: race_deadline violating evidence. *)
[@@@warning "-32-34-37"]

let race sw f =
  Ox.Concurrent.race ~sw
    [
      f;
      (fun () ->
        Eio.Fiber.yield ();
        Eio.Time.sleep (assert false) 1.;
        Error ());
    ]

let first sw f =
  Ox.Concurrent.race_first ~sw
    [
      f;
      (fun () ->
        Eio.Time.sleep (assert false) 1.;
        Error ());
    ]

let any f = Eio.Fiber.any [ f; (fun () -> Eio.Time.sleep (assert false) 1.) ]

module C = Ox.Concurrent
module T = Eio.Time

let alias sw f =
  C.race_first ~sw
    [
      f;
      (fun () ->
        T.sleep (assert false) 1.;
        Error ());
    ]
