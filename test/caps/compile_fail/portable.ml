(* ^ncaps-vlwm: a capability is a single-domain value. An object does not cross into a
   portable closure (what a closure sent to another domain must be), so a capability
   cannot ride along to another domain; mint one per domain there. Must not compile. *)
open Ox_caps

type thunk = unit -> string option

let on_another_domain (f : thunk @ portable) = f ()
let send (caps : Cap.env) = on_another_domain (fun () -> Cap_sys.getenv_opt ~caps "HOME")
