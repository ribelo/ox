let command ~caps:_ text = Sys.command text
let chdir ~caps:_ dir = Sys.chdir dir
let getenv ~caps:_ name = Sys.getenv name
let getenv_opt ~caps:_ name = Sys.getenv_opt name
let signal ~caps:_ n behavior = (Sys.signal [@alert "-unsafe_multidomain"]) n behavior

let set_signal ~caps:_ n behavior =
  (Sys.set_signal [@alert "-unsafe_multidomain"]) n behavior

let time ~caps:_ () = Sys.time ()
let readdir ~caps:_ path = Sys.readdir path
let remove ~caps:_ path = Sys.remove path
let rename ~caps:_ src dst = Sys.rename src dst
let mkdir ~caps:_ path perm = Sys.mkdir path perm
let rmdir ~caps:_ path = Sys.rmdir path

let urandom ~caps:_ n =
  In_channel.with_open_bin "/dev/urandom" (fun channel -> really_input_string channel n)
