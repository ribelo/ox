(* ^safe-cank ^safe-763t ^safe-f1yz *)
let protected ~caps path =
  let fd = Ox_caps.Cap_unix.openfile ~caps path [ Unix.O_RDONLY ] 0 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> Unix.fstat fd)

let scoped ~caps ~sw path =
  Ox.Resource.use_in_scope ~sw
    (fun () -> Ox_caps.Cap_unix.openfile ~caps path [ Unix.O_RDONLY ] 0)
    Unix.close

let registered ~caps ~sw path =
  let fd = Ox_caps.Cap_unix.openfile ~caps path [ Unix.O_RDONLY ] 0 in
  let alias = fd in
  Eio.Switch.on_release sw (fun () -> Unix.close alias)

let manual ~caps path =
  let fd = Ox_caps.Cap_unix.openfile ~caps path [ Unix.O_RDONLY ] 0 in
  let value =
    try Unix.fstat fd
    with ex ->
      Unix.close fd;
      raise ex
  in
  Unix.close fd;
  value

let tuple ~caps command =
  let channels = Ox_caps.Cap_unix.open_process_full ~caps command [||] in
  Fun.protect
    ~finally:(fun () -> ignore (Unix.close_process_full channels))
    (fun () -> ())

module Cap_unix = struct
  let openfile _ = 1
end

let shadow path = Cap_unix.openfile path
