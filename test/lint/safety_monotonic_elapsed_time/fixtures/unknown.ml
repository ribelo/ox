(* The caller owns the unknown numeric callback. *)

let sleep clock obscure = Eio.Time.sleep clock (obscure (Eio.Time.now clock))

let compare clock obscure =
  let started = Eio.Time.now clock in
  obscure (Eio.Time.now clock) > started

let fractional clock floor =
  let stamp = Eio.Time.now clock in
  stamp -. floor stamp

let different_reads clock = Eio.Time.now clock -. floor (Eio.Time.now clock)
