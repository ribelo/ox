let fork ~caps:_ () = Unix.fork ()
let execv ~caps:_ prog args = Unix.execv prog args
let execve ~caps:_ prog args env = Unix.execve prog args env
let execvp ~caps:_ prog args = Unix.execvp prog args
let execvpe ~caps:_ prog args env = Unix.execvpe prog args env
let create_process ~caps:_ prog args i o e = Unix.create_process prog args i o e

let create_process_env ~caps:_ prog args env i o e =
  Unix.create_process_env prog args env i o e

let open_process_in ~caps:_ command = Unix.open_process_in command
let open_process_out ~caps:_ command = Unix.open_process_out command
let open_process ~caps:_ command = Unix.open_process command
let open_process_full ~caps:_ command env = Unix.open_process_full command env
let open_process_args_in ~caps:_ prog args = Unix.open_process_args_in prog args
let open_process_args_out ~caps:_ prog args = Unix.open_process_args_out prog args
let open_process_args ~caps:_ prog args = Unix.open_process_args prog args
let system ~caps:_ command = Unix.system command
let _exit ~caps:_ code = Unix._exit code
let chdir ~caps:_ dir = Unix.chdir dir
let getenv ~caps:_ name = Unix.getenv name
let environment ~caps:_ () = Unix.environment ()
let putenv ~caps:_ name value = (Unix.putenv [@alert "-unsafe_multidomain"]) name value
let kill ~caps:_ pid signal = Unix.kill pid signal
let sigprocmask ~caps:_ command signals = Unix.sigprocmask command signals
let time ~caps:_ () = Unix.time ()
let gettimeofday ~caps:_ () = Unix.gettimeofday ()
let openfile ~caps:_ path flags perm = Unix.openfile path flags perm

let openfile_write ~caps:_ path flags perm =
  if List.mem Unix.O_RDONLY flags || List.mem Unix.O_RDWR flags then
    invalid_arg "Cap_unix.openfile_write: read access is not allowed";
  Unix.openfile path (Unix.O_WRONLY :: flags) perm

let open_dev_null () = Unix.openfile "/dev/null" [ Unix.O_WRONLY; Unix.O_CLOEXEC ] 0
let opendir ~caps:_ path = Unix.opendir path
let unlink ~caps:_ path = Unix.unlink path
let rename ~caps:_ src dst = Unix.rename src dst
let mkdir ~caps:_ path perm = Unix.mkdir path perm
let rmdir ~caps:_ path = Unix.rmdir path
let chmod ~caps:_ path perm = Unix.chmod path perm
let truncate ~caps:_ path length = Unix.truncate path length
let symlink ~caps:_ ?to_dir src dst = Unix.symlink ?to_dir src dst
let link ~caps:_ ?follow src dst = Unix.link ?follow src dst

let socket ~caps:_ ?cloexec domain kind protocol =
  Unix.socket ?cloexec domain kind protocol

let open_connection ~caps:_ address = Unix.open_connection address
let establish_server ~caps:_ serve address = Unix.establish_server serve address
