(* ^nlet-4eh4: after let%bind a yielding value still cannot enter an unyielding closure. *)
(* expect: yielding *)
let short (f : (unit -> unit) @ local unyielding) = f () [@nontail]

let use (io : (unit -> unit) @ local yielding) (r : (int, string) result) =
  let%bind x = r in
  short (fun () -> io ());
  Ok x
