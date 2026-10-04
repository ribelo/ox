let command ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) text = Sys.command text
let chdir ~caps:(_caps : < Cap.chdir ; .. >) dir = Sys.chdir dir
let getenv ~caps:(_caps : < Cap.env ; .. >) name = Sys.getenv name
let getenv_opt ~caps:(_caps : < Cap.env ; .. >) name = Sys.getenv_opt name

let signal ~caps:(_caps : < Cap.signal ; .. >) n behavior =
  (Sys.signal [@alert "-unsafe_multidomain"]) n behavior

let set_signal ~caps:(_caps : < Cap.signal ; .. >) n behavior =
  (Sys.set_signal [@alert "-unsafe_multidomain"]) n behavior

let time ~caps:(_caps : < Cap.time ; .. >) () = Sys.time ()
let readdir ~caps:(_caps : < Cap.fs_read ; .. >) path = Sys.readdir path
let remove ~caps:(_caps : < Cap.fs_write ; .. >) path = Sys.remove path
let rename ~caps:(_caps : < Cap.fs_write ; .. >) src dst = Sys.rename src dst
let mkdir ~caps:(_caps : < Cap.fs_write ; .. >) path perm = Sys.mkdir path perm
let rmdir ~caps:(_caps : < Cap.fs_write ; .. >) path = Sys.rmdir path

let urandom ~caps:(_caps : < Cap.random ; Cap.fs_read ; .. >) n =
  In_channel.with_open_bin "/dev/urandom" (fun channel -> really_input_string channel n)
