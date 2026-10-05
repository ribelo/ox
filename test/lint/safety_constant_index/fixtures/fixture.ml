(* ^safe-rxya: literal array at its exact upper bound. *)
let upper () = Array.get [| 1 |] 1

(* ^safe-d197: lengths are decoded bytes, not source spelling. *)
let escaped_upper () = String.get "\x41\n" 2
let escaped_valid () = String.get "\x41\n" 1
let unicode_upper () = String.get "é" 2
let unicode_valid () = String.get "é" 1
let empty_string () = "".[0]
let negative_string () = String.get "ab" (-1)
let array_empty () = [||].(0)
let array_negative () = Array.get [| 1; 2 |] (-1)
let array_valid () = [| 1; 2 |].(1)

(* ^safe-xd2e ^safe-tlyw: resolved opens, module and local value aliases. *)
module A = Stdlib.Array
module S = Stdlib.String
module B = Stdlib.Bytes

let module_alias () = A.get [| 1 |] 1

let opened () =
  let open S in
  get "x" 1

let value_alias () =
  let get = String.get in
  let read = get in
  read "x" 1

let bound_array () =
  let a = [| 1 |] in
  let b = a in
  Array.get b 1

let bound_index () =
  let i = -1 in
  String.get "x" i

(* ^safe-d197: bytes only from a proved local of_string origin. *)
let bytes_upper () = Bytes.get (Bytes.of_string "\x41\n") 2
let bytes_empty () = B.get (B.of_string "") 0
let bytes_negative () = Bytes.get (Bytes.of_string "x") (-1)
let bytes_valid () = Bytes.get (Bytes.of_string "é") 1

let bound_bytes () =
  let of_string = Bytes.of_string in
  let b = of_string "a" in
  B.get b 1

(* ^safe-xd2e ^safe-tlyw: legitimate same-spelled operations stay clean. *)
let shadow_value () =
  let get _ _ = 42 in
  get [| 1 |] 7

let shadow_parameter get = get [| 1 |] 7

let shadow_capture () =
  let get = String.get in
  let read = get in
  let get _ _ = 'z' in
  (read "a" 0, get "a" 1)

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

let shadow_module_array () = [| 1 |].(7)
let shadow_module_string () = "a".[7]
let shadow_origin () = Bytes.get (Bytes.of_string "a") 7

let shadow_alias () =
  let get = Array.get in
  get [| 1 |] 7

(* ^safe-xd2e: unknown lengths, indexes and wrappers are outside the horizon. *)
let dynamic_array a = Stdlib.Array.get a 99
let dynamic_string s = Stdlib.String.get s 99
let dynamic_bytes b = Stdlib.Bytes.get b 99
let dynamic_index i = Stdlib.Array.get [| 1 |] i
let dynamic_of_string s = Stdlib.Bytes.get (Stdlib.Bytes.of_string s) 99
let make_bytes () = Stdlib.Bytes.get (Stdlib.Bytes.make 8 'x') 7

let wrapped_get () =
  let get _ _ = 42 in
  get [| 1 |] 99

let wrapped_origin () =
  let create _ = [| 1; 2 |] in
  A.get (create [| 1 |]) 1

let rebound_ref () =
  let a = ref [| 1 |] in
  a := [| 1; 2 |];
  A.get !a 1

let unknown_branch b =
  let a = if b then [| 1 |] else [| 1; 2 |] in
  A.get a 1

(* Canonical getter identities must not come from this local Stdlib. *)
module Stdlib = struct
  module Array = struct
    let get _ _ = 42
  end

  module String = struct
    let get _ _ = 'z'
  end

  module Bytes = struct
    let of_string _ = 42
    let get _ _ = 'z'
  end
end

let shadow_stdlib_array () = Stdlib.Array.get [| 1 |] 99
let shadow_stdlib_string () = Stdlib.String.get "a" 99
let shadow_stdlib_bytes () = Stdlib.Bytes.get (Stdlib.Bytes.of_string "a") 99
