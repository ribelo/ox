[@@@ox_lint.fixture "ox-caps-fs-write: deliberate negative fixture"]

let violation () = Stdlib.open_out "x"
