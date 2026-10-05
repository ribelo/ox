(* ^safe-jwwj ^safe-fr73 ^safe-tlyw: preserve exact warning-producing controls
   only in the declared nested evidence project, never run them. *)
let partial fd =
  let _ = Unix.write fd in
  ()

let checked_pattern fd bytes =
  let 0 = Unix.read fd bytes 0 4 in
  ()

let checked_tuple fd bytes =
  let (0 as _count), address = Unix.recvfrom fd bytes 0 4 [] in
  address

let send fd bytes =
  let count = Unix.send fd bytes 0 4 [] in
  ()

let shadowed_count fd bytes =
  let count = Unix.write fd bytes 0 4 in
  let count = 4 in
  count
