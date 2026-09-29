(* ^ncaps-vlwm: the control for portable.ml — the same portable closure capturing a plain
   string compiles, so portable.ml fails because the captured value is a capability. *)
type thunk = unit -> string option

let on_another_domain (f : thunk @ portable) = f ()
let send (name : string) = on_another_domain (fun () -> Some name)
