(* ^ncaps-aw5n: a program narrowed its powerbox to exclude Cap.exec, so a function
   requiring Cap.exec cannot be called with it. Must not compile. *)
open Ox_caps

let program (powerbox : Cap.all_caps) =
  let narrowed = (powerbox :> < Cap.fork ; Cap.fs_read >) in
  Cap_unix.system ~caps:narrowed "true"
