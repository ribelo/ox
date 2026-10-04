(* ^ncapslint-8jcy: real tokens, explicit and captured argument authority. *)
let visible ~caps () = Ox_caps.Cap_unix.fork ~caps ()

let create ~caps =
  let hidden () = Ox_caps.Cap_unix.fork ~caps () in
  hidden

type deps = { caps : Ox_caps.Cap.fork }

let via_record (deps : deps) () = Ox_caps.Cap_unix.fork ~caps:deps.caps ()

let via_alias ~caps () =
  let alias = caps in
  Ox_caps.Cap_unix.fork ~caps:alias ()
