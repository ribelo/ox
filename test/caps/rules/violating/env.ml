[@@@ox_lint.fixture "ox-caps-env: deliberate negative fixture"]

let violation () = Sys.getenv "HOME"
