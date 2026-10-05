(* ^safe-jwwj ^safe-fr73 ^safe-tlyw: returned/used counts, aliases and shadowing. *)
let read fd bytes = Unix.read fd bytes 0 4

let used fd bytes =
  let count = Unix.write fd bytes 0 4 in
  count

let eof fd bytes = match Unix.read fd bytes 0 4 with 0 -> None | count -> Some count

let tuple fd bytes =
  let count, _ = Unix.recvfrom fd bytes 0 4 [] in
  count

let alias_tuple fd bytes =
  let ((_, address) as result) = Unix.recvfrom fd bytes 0 4 [] in
  (address, result)

let partial fd =
  let _pending = Unix.write fd in
  ()

let unrelated () =
  let _ = 4 in
  ()

let unknown write fd bytes = ignore (write fd bytes 0 4)

let shadow fd bytes =
  let read _ _ _ _ = 4 in
  ignore (read fd bytes 0 4)

module Fake = struct
  let write _ _ _ _ = 4
end

module Alias = Fake

let fake_alias fd bytes = ignore (Alias.write fd bytes 0 4)

let fake_unix fd bytes =
  let module Unix = Fake in
  ignore (Unix.write fd bytes 0 4)

let fake_ignore fd bytes =
  let ignore x = x in
  ignore (Unix.read fd bytes 0 4)

let fake_ignore_module fd bytes =
  let module Stdlib = struct
    let ignore x = x
  end in
  Stdlib.ignore (Unix.read fd bytes 0 4)

let forward ~caps:(_ : < Ox_caps.Cap.fs_read ; .. >) fd bytes off len =
  Unix.write fd bytes off len

let wrapper ~caps fd bytes =
  let count = forward ~caps fd bytes 0 4 in
  count

let renamed_wrapper ~caps fd bytes =
  let forward ~caps:(_ : < Ox_caps.Cap.fs_read ; .. >) _ _ _ _ = 4 in
  ignore (forward ~caps fd bytes 0 4)

let transform fd bytes off len = Unix.write fd bytes off len + 1
let transformed_wrapper fd bytes = ignore (transform fd bytes 0 4)
let complete source sink = Eio.Flow.copy source sink

(* This corpus-shaped loop deliberately consumes each count. It is not a lint proof of correctness. *)
let write_loop fd bytes =
  let total = Bytes.length bytes in
  let rec loop written =
    if written < total then
      match Unix.write fd bytes written (total - written) with
      | 0 -> failwith "zero progress"
      | count -> loop (written + count)
  in
  loop 0

let consumed_then_ignored fd bytes =
  let count = Unix.write fd bytes 0 4 in
  let result = count + 1 in
  ignore count;
  result

let returned_alias fd bytes =
  let count = Unix.write fd bytes 0 4 in
  let copy = count in
  copy

let shadowed_ignore_count fd bytes =
  let count = Unix.write fd bytes 0 4 in
  let ignore x = x in
  ignore count

let shadowed_operation_count fd bytes =
  let write _ _ _ _ = 4 in
  let count = write fd bytes 0 4 in
  let copy = count in
  ignore copy

let heap_retained fd bytes =
  let count = Unix.write fd bytes 0 4 in
  let slot = ref count in
  ignore slot
