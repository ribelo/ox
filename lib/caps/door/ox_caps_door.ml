(* ^ncaps-uiq6: only the Door and Ox_test depend on this library. The concrete
   tokens live here, not in the public ox_caps.Cap interface. *)
type fork = Fork
type exec = Exec
type exit = Exit
type chdir = Chdir
type env = Env
type signal = Signal
type time = Time
type random = Random
type stdin = Stdin
type stdout = Stdout
type stderr = Stderr
type fs_read = Fs_read
type fs_write = Fs_write
type tmp = Tmp
type network = Network

let powerbox () =
  object
    method fork = Fork
    method exec = Exec
    method exit = Exit
    method chdir = Chdir
    method env = Env
    method signal = Signal
    method time = Time
    method random = Random
    method stdin = Stdin
    method stdout = Stdout
    method stderr = Stderr
    method fs_read = Fs_read
    method fs_write = Fs_write
    method tmp = Tmp
    method network = Network
  end
