(* RFC 4648 basic base64; local to the copied v1 WebSocket codec. *)
let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let encode_string input =
  let n = String.length input in
  let out = Bytes.create (4 * ((n + 2) / 3)) in
  for i = 0 to ((n + 2) / 3) - 1 do
    let src = i * 3 and dst = i * 4 in
    let a = Char.code input.[src] in
    let b = if src + 1 < n then Char.code input.[src + 1] else 0 in
    let c = if src + 2 < n then Char.code input.[src + 2] else 0 in
    Bytes.set out dst alphabet.[a lsr 2];
    Bytes.set out (dst + 1) alphabet.[((a land 3) lsl 4) lor (b lsr 4)];
    Bytes.set out (dst + 2)
      (if src + 1 < n then alphabet.[((b land 15) lsl 2) lor (c lsr 6)] else '=');
    Bytes.set out (dst + 3) (if src + 2 < n then alphabet.[c land 63] else '=')
  done;
  Bytes.unsafe_to_string out
