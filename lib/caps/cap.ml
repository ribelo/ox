module Token = struct
  type fork = unit
  type exec = unit
  type exit = unit
  type chdir = unit
  type env = unit
  type signal = unit
  type time = unit
  type random = unit
  type stdin = unit
  type stdout = unit
  type stderr = unit
  type fs_read = unit
  type fs_write = unit
  type tmp = unit
  type network = unit
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

let powerbox () : all_caps =
  object
    method fork = ()
    method exec = ()
    method exit = ()
    method chdir = ()
    method env = ()
    method signal = ()
    method time = ()
    method random = ()
    method stdin = ()
    method stdout = ()
    method stderr = ()
    method fs_read = ()
    method fs_write = ()
    method tmp = ()
    method network = ()
  end
