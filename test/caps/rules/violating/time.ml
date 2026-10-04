[@@@ox_lint.fixture "ox-caps-time: deliberate negative fixture"]

let violation () = Unix.gettimeofday ()
