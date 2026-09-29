module Token = struct
  type fork = Ox_caps_door.fork
  type exec = Ox_caps_door.exec
  type exit = Ox_caps_door.exit
  type chdir = Ox_caps_door.chdir
  type env = Ox_caps_door.env
  type signal = Ox_caps_door.signal
  type time = Ox_caps_door.time
  type random = Ox_caps_door.random
  type stdin = Ox_caps_door.stdin
  type stdout = Ox_caps_door.stdout
  type stderr = Ox_caps_door.stderr
  type fs_read = Ox_caps_door.fs_read
  type fs_write = Ox_caps_door.fs_write
  type tmp = Ox_caps_door.tmp
  type network = Ox_caps_door.network
end

type fork = < fork : Token.fork >
type exec = < exec : Token.exec >
type exit = < exit : Token.exit >
type chdir = < chdir : Token.chdir >
type env = < env : Token.env >
type signal = < signal : Token.signal >
type time = < time : Token.time >
type random = < random : Token.random >
type stdin = < stdin : Token.stdin >
type stdout = < stdout : Token.stdout >
type stderr = < stderr : Token.stderr >
type fs_read = < fs_read : Token.fs_read >
type fs_write = < fs_write : Token.fs_write >
type tmp = < tmp : Token.tmp >
type network = < network : Token.network >
type process = < fork ; exec >
type console = < stdin ; stdout ; stderr >
type fs = < fs_read ; fs_write ; tmp >

type all_caps =
  < fork
  ; exec
  ; exit
  ; chdir
  ; env
  ; signal
  ; time
  ; random
  ; stdin
  ; stdout
  ; stderr
  ; fs_read
  ; fs_write
  ; tmp
  ; network >

type no_caps = < >
