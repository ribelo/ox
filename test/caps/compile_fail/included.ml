(* ^ncaps-aw5n: the control for excluded.ml — the same program narrowed to a powerbox that
   keeps Cap.exec compiles, so excluded.ml fails for the missing capability alone. *)
open Ox_caps

let program (powerbox : Cap.all_caps) =
  let narrowed = (powerbox :> < Cap.fork ; Cap.exec ; Cap.fs_read >) in
  Cap_unix.system ~caps:narrowed "true"
