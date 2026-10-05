(* ^safe-jwwj ^safe-qmcw ^safe-t50j: supported native contracts and disposal sinks. *)
let read fd bytes = ignore (Unix.read fd bytes 0 4 [@expect_stream])

let write fd bytes =
  let _ = (Unix.write fd bytes 0 4 [@expect_stream]) in
  ()

let single_write fd bytes =
  let _count = (Unix.single_write fd bytes 0 4 [@expect_stream]) in
  ()

let recv fd bytes = ignore (Unix.recv fd bytes 0 4 [] [@expect_socket])

let send fd bytes =
  let _count = (Unix.send fd bytes 0 4 [] [@expect_socket]) in
  ()

let recvfrom fd bytes =
  let _, address = (Unix.recvfrom fd bytes 0 4 [] [@expect_datagram]) in
  address

let unused_tuple fd bytes =
  let _count, address = (Unix.recvfrom fd bytes 0 4 [] [@expect_datagram]) in
  address

let sendto fd bytes addr =
  ignore (Unix.sendto fd bytes 0 4 [] addr [@expect_datagram])

let input channel bytes =
  let _ = (Stdlib.input channel bytes 0 4 [@expect_stream]) in
  ()

let shadowed_count fd bytes =
  let _count = (Unix.write fd bytes 0 4 [@expect_stream]) in
  let count = 4 in
  count

let full_tuple fd bytes =
  ignore (Unix.recvfrom fd bytes 0 4 [] [@expect_datagram])

module Native = Unix

let module_alias fd bytes = ignore (Native.write fd bytes 0 4 [@expect_stream])

let local_alias fd bytes =
  let write = Unix.write in
  ignore (write fd bytes 0 4 [@expect_stream])

let opened fd bytes =
  let open Unix in
  ignore (read fd bytes 0 4 [@expect_stream])

let discard = Stdlib.ignore
let ignore_alias fd bytes = discard (Unix.read fd bytes 0 4 [@expect_stream])

let forward ~caps:(_ : < Ox_caps.Cap.fs_read ; .. >) fd bytes offset length =
  Unix.write fd bytes offset length

let wrapper ~caps fd bytes =
  ignore (forward ~caps fd bytes 0 4 [@expect_stream])

let wrapper_alias ~caps fd bytes =
  let write = forward in
  let _ = (write ~caps fd bytes 0 4 [@expect_stream]) in
  ()

let wrapped_receive ~caps:(_ : < Ox_caps.Cap.fs_read ; .. >) fd bytes offset
    length flags =
  Unix.recvfrom fd bytes offset length flags

let wrapper_tuple ~caps fd bytes =
  let _, address = (wrapped_receive ~caps fd bytes 0 4 [] [@expect_datagram]) in
  address

module Forward = struct
  let write fd bytes off len = Unix.write fd bytes off len
end

module Forward_alias = Forward

let module_wrapper fd bytes =
  ignore (Forward_alias.write fd bytes 0 4 [@expect_stream])

let apply_ignore fd bytes = ignore @@ (Unix.write fd bytes 0 4 [@expect_stream])
let pipe_ignore fd bytes = (Unix.read fd bytes 0 4 [@expect_stream]) |> ignore

let bound_ignore fd bytes =
  let count = (Unix.write fd bytes 0 4 [@expect_stream]) in
  ignore count

let result_alias fd bytes =
  let count = (Unix.write fd bytes 0 4 [@expect_stream]) in
  let copy = count in
  ignore copy

let local_ignore_alias fd bytes =
  let count = (Unix.read fd bytes 0 4 [@expect_stream]) in
  let drop = ignore in
  drop count

let tuple_ignore fd bytes =
  let count, address = (Unix.recvfrom fd bytes 0 4 [] [@expect_datagram]) in
  let copy = count in
  ignore copy;
  address

let whole_tuple_alias fd bytes =
  let result = (Unix.recvfrom fd bytes 0 4 [] [@expect_datagram]) in
  let copy = result in
  ignore copy

let alias_wildcard fd bytes =
  let count = (Unix.write fd bytes 0 4 [@expect_stream]) in
  let copy = count in
  let _ = copy in
  ()
