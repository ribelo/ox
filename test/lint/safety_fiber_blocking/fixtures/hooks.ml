(* ^safe-r5ye: only the job crosses to native; argument computation and hooks do not. *)
let argument ~pool () = Eio_main.run (fun _ ->
  ignore (Ox_blocking.run ~pool (let () = Unix.sleepf 0.01 in fun () -> ())))
let settled ~pool () = Eio_main.run (fun _ ->
  ignore (Ox_blocking.run ~pool ~on_settled:(fun _ -> Thread.delay 0.01) (fun () -> ())))
let cancelled ~pool () = Eio_main.run (fun _ ->
  ignore (Ox_blocking.run ~pool ~on_cancel:(fun () -> Unix.sleepf 0.01) (fun () -> ())))
