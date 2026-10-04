[@@@ox_lint.fixture "ox-caps-signal: deliberate negative fixture"]

let violation () = Unix.kill 0 0
