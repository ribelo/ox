[@@@ox_lint.fixture "ox-caps-network: deliberate negative fixture"]

let violation () = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0
