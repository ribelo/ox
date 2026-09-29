(* ^ncaps-znyh ^ncaps-rwnz: every bare standard channel value is forbidden. *)
let write () = output_string stdout "not allowed"
let warn () = output_string stderr "not allowed"
let read () = input_line stdin
let file_read path = In_channel.with_open_text path In_channel.input_all
let file_write path = Out_channel.with_open_text path (fun channel -> Out_channel.output_string channel "x")
