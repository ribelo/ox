[@@@ox_lint.fixture "ox-caps-fs-read: deliberate negative fixture"]

let violation () = Stdlib.open_in "x"
