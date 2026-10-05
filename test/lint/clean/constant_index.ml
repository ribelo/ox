(* ^safe-d197 ^safe-xd2e ^safe-tlyw: valid bounds and legitimate counterexamples. *)
let array_first () = [| 1; 2 |].(0)
let array_last () = Array.get [| 1; 2 |] 1
let string_last () = "\x41\n".[1]
let unicode_byte () = String.get "é" 1
let bytes_last () = Bytes.get (Bytes.of_string "é") 1

let checked_index a i =
  if i >= 0 && i < Array.length a then Ok (Array.get a i) else Error `Index_out_of_bounds

module Array = struct
  let get _ _ = 42
end

module String = struct
  let get _ _ = 'z'
end

module Bytes = struct
  let of_string _ = Stdlib.Bytes.make 8 'x'
  let get = Stdlib.Bytes.get
end

let shadow_array () = [| 1 |].(7)
let shadow_string () = "a".[7]
let shadow_origin () = Bytes.get (Bytes.of_string "a") 7

let shadow_value () =
  let get _ _ = 42 in
  get [| 1 |] 7

let unknown_array a = Stdlib.Array.get a 99
let unknown_string s = Stdlib.String.get s 99
let unknown_bytes b = Stdlib.Bytes.get b 99
let unknown_index i = Stdlib.Array.get [| 1 |] i
let unknown_origin s = Stdlib.Bytes.get (Stdlib.Bytes.of_string s) 99

let unknown_branch b =
  let a = if b then [| 1 |] else [| 1; 2 |] in
  Stdlib.Array.get a 1
