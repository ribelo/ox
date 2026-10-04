(* ^ncapslint-5rxe: minimized from the corresponding real parser-hole source. *)
let violation flow = { flow :> T.t; fd = Unix.socket PF_UNIX SOCK_STREAM 0 }
