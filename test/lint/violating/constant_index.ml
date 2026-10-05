(* ^safe-rxya ^safe-d197: demonstrated defects, not policy prohibitions. *)
let array_upper () = [| 1 |].(1)
let array_empty () = Array.get [||] 0
let array_negative () = Array.get [| 1 |] (-1)
let string_upper () = "\x41\n".[2]
let string_empty () = String.get "" 0
let string_negative () = String.get "a" (-1)
let bytes_upper () = Bytes.get (Bytes.of_string "\x41\n") 2

module A = Stdlib.Array

let alias_upper () = A.get [| 1 |] 1

let value_alias () =
  let get = String.get in
  get "a" 1
