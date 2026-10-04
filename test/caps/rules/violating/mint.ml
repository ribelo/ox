(* ^ncapslint-2606: compiled negative evidence in a separate Dune project. *)

let violation () = Ox_app.with_powerbox (fun _ -> ())

module Door = Ox_caps_door

type token = Door.fork
