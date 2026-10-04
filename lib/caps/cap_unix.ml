let fork ~caps:(_caps : < Cap.fork ; .. >) () = Unix.fork ()
let execv ~caps:(_caps : < Cap.exec ; .. >) prog args = Unix.execv prog args
let execve ~caps:(_caps : < Cap.exec ; .. >) prog args env = Unix.execve prog args env
let execvp ~caps:(_caps : < Cap.exec ; .. >) prog args = Unix.execvp prog args
let execvpe ~caps:(_caps : < Cap.exec ; .. >) prog args env = Unix.execvpe prog args env

let create_process ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) prog args i o e =
  Unix.create_process prog args i o e

let create_process_env ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) prog args env i o e =
  Unix.create_process_env prog args env i o e

let open_process_in ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) command =
  Unix.open_process_in command

let open_process_out ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) command =
  Unix.open_process_out command

let open_process ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) command =
  Unix.open_process command

let open_process_full ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) command env =
  Unix.open_process_full command env

let open_process_args_in ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) prog args =
  Unix.open_process_args_in prog args

let open_process_args_out ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) prog args =
  Unix.open_process_args_out prog args

let open_process_args ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) prog args =
  Unix.open_process_args prog args

let system ~caps:(_caps : < Cap.fork ; Cap.exec ; .. >) command = Unix.system command
let _exit ~caps:(_caps : < Cap.exit ; .. >) code = Unix._exit code
let chdir ~caps:(_caps : < Cap.chdir ; .. >) dir = Unix.chdir dir
let getenv ~caps:(_caps : < Cap.env ; .. >) name = Unix.getenv name
let environment ~caps:(_caps : < Cap.env ; .. >) () = Unix.environment ()

let putenv ~caps:(_caps : < Cap.env ; .. >) name value =
  (Unix.putenv [@alert "-unsafe_multidomain"]) name value

let kill ~caps:(_caps : < Cap.signal ; .. >) pid signal = Unix.kill pid signal

let sigprocmask ~caps:(_caps : < Cap.signal ; .. >) command signals =
  Unix.sigprocmask command signals

let time ~caps:(_caps : < Cap.time ; .. >) () = Unix.time ()
let gettimeofday ~caps:(_caps : < Cap.time ; .. >) () = Unix.gettimeofday ()

let openfile ~caps:(_caps : < Cap.fs_read ; Cap.fs_write ; .. >) path flags perm =
  Unix.openfile path flags perm

let openfile_write ~caps:(_caps : < Cap.fs_write ; .. >) path flags perm =
  if List.mem Unix.O_RDONLY flags || List.mem Unix.O_RDWR flags then
    invalid_arg "Cap_unix.openfile_write: read access is not allowed";
  Unix.openfile path (Unix.O_WRONLY :: flags) perm

let open_dev_null ~caps:(_caps : < Cap.fs_write ; .. >) () =
  Unix.openfile "/dev/null" [ Unix.O_WRONLY; Unix.O_CLOEXEC ] 0

let opendir ~caps:(_caps : < Cap.fs_read ; .. >) path = Unix.opendir path
let unlink ~caps:(_caps : < Cap.fs_write ; .. >) path = Unix.unlink path
let rename ~caps:(_caps : < Cap.fs_write ; .. >) src dst = Unix.rename src dst
let mkdir ~caps:(_caps : < Cap.fs_write ; .. >) path perm = Unix.mkdir path perm
let rmdir ~caps:(_caps : < Cap.fs_write ; .. >) path = Unix.rmdir path
let chmod ~caps:(_caps : < Cap.fs_write ; .. >) path perm = Unix.chmod path perm
let truncate ~caps:(_caps : < Cap.fs_write ; .. >) path length = Unix.truncate path length

let symlink ~caps:(_caps : < Cap.fs_write ; .. >) ?to_dir src dst =
  Unix.symlink ?to_dir src dst

let link ~caps:(_caps : < Cap.fs_write ; .. >) ?follow src dst = Unix.link ?follow src dst

let socket ~caps:(_caps : < Cap.network ; .. >) ?cloexec domain kind protocol =
  Unix.socket ?cloexec domain kind protocol

let open_connection ~caps:(_caps : < Cap.network ; .. >) address =
  Unix.open_connection address

let establish_server ~caps:(_caps : < Cap.network ; Cap.fork ; .. >) serve address =
  Unix.establish_server serve address
