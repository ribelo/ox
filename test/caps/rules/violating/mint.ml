(* ^ncapslint-nf4t ^ncapslint-w2tq: never run, compiled rule evidence. *)
let violation () = Ox_app.with_powerbox (fun _ -> ())

module Door = Ox_caps_door

type token = Door.fork
