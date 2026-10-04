[@@@ox_lint.fixture "ox-caps-chdir: deliberate negative fixture"]

let violation () = Sys.chdir "."
