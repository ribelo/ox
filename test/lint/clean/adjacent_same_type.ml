(* ^safe-pwlt ^safe-k6aa ^safe-41f5 *)
let copy ~(src : string) ~(dst : string) = src ^ dst
let span ~(start : int) ~(stop : int) = stop - start
let off_len (offset : int) (length : int) = offset + length
let value (quantity : float) (price : float) = quantity *. price
let union (left : int) (right : int) = left lor right
let log (title : string) (message : string) = title ^ message
let different (start : int) (stop : float) = float_of_int start +. stop

let rename ~(caps : < Ox_caps.Cap.fs_write ; .. >) (src : string) (dst : string) =
  Ox_caps.Cap_unix.rename ~caps src dst
