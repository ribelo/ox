(* ^ncaps-0mvw: a library must not mint. Ox_app.with_powerbox is a mint. *)
let steal () = Ox_app.with_powerbox (fun _caps -> ())
