(* ^safe-cank ^safe-763t ^safe-mzdt *)
let leaked ~caps path = Ox_caps.Cap_unix.openfile ~caps path [Unix.O_RDONLY] 0
let unrelated ~caps path other =
  let fd = Ox_caps.Cap_unix.openfile ~caps path [Unix.O_RDONLY] 0 in
  Fun.protect ~finally:(fun () -> Unix.close other) (fun () -> Unix.fstat fd)
let empty_release ~caps ~sw path =
  Ox.Resource.use_in_scope ~sw
    (fun () -> Ox_caps.Cap_unix.openfile ~caps path [Unix.O_RDONLY] 0) (fun _ -> ())
let partial_tuple ~caps command =
  let input, _output, _error = Ox_caps.Cap_unix.open_process_full ~caps command [||] in
  Fun.protect ~finally:(fun () -> close_in input) (fun () -> input_line input)
let guarded_close fd = try Unix.close fd with _ -> ()
let validation_gap ~caps path =
  try
    let fd = Ox_caps.Cap_unix.openfile ~caps path [Unix.O_RDONLY] 0 in
    let _ = Unix.fstat fd in guarded_close fd
  with Unix.Unix_error _ -> ()
let wrong_scoped_result ~caps ~sw path other =
  Ox.Resource.use_in_scope ~sw
    (fun () -> let _leaked = Ox_caps.Cap_unix.openfile ~caps path [Unix.O_RDONLY] 0 in other)
    Unix.close
