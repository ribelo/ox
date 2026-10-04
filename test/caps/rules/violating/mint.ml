[@@@ox_lint.fixture "ox-caps-mint: deliberate negative fixture"]

let violation () = Ox_app.with_powerbox (fun _ -> ())

module Door = Ox_caps_door

type token = Door.fork
