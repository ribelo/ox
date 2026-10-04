(* ^ncaps-znyh: bare channels and argumentless file opens lack authority. *)
let write () = output_string stdout "not allowed"
let warn () = output_string stderr "not allowed"
let read () = input_line stdin
let file_read () = In_channel.with_open_text "file" In_channel.input_all
let file_write () = Out_channel.with_open_text "file" (fun channel -> Out_channel.output_string channel "x")
