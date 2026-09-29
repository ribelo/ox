(* ^ncaps-aw5n ^ncaps-0mvw: a capability cannot be forged by writing an object with the
   right method name — the method's type is an abstract token only Ox_caps produces. Must
   not compile. *)
open Ox_caps

let forged : Cap.exec =
  object
    method exec = ()
  end

let run () = Cap_unix.system ~caps:forged "true"
