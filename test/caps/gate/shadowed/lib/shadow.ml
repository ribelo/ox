(* ^ncaps-znyh ^ncaps-rwnz: a local channel is not Stdlib.stdout. *)
type collected = { stdout : out_channel }
let use channel = let stdout = channel in output_string stdout "safe"
let pack channel = { stdout = channel }
let use_mode ?(stdout = `Discard) () = ignore stdout
