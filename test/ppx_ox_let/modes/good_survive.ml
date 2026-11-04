(* ^nlet-4eh4: a local value and a yielding value are used after let%bind. *)
let use (s : int ref @ local) (io : (unit -> unit) @ local yielding) (r : (int, string) result) =
  let%bind x = r in
  s := x;
  io ();
  let%map y = Ok (x + 1) in
  s := y
