type fork
(** Sealed tokens for the capabilities exposed by [Ox_caps.Cap.Token] (^ncaps-uiq6). *)

type exec
type exit
type chdir
type env
type signal
type time
type random
type stdin
type stdout
type stderr
type fs_read
type fs_write
type tmp
type network

(** Cancellation and finalizers: Suspension: never suspends; this constructor builds an
    object of tokens. Cancellation: not a cancellation point; no Eio operation is called.
    Finalizers: none are registered. Locking: no lock is acquired. ^nlintd-a7oq *)

val powerbox :
  unit ->
  < fork : fork
  ; exec : exec
  ; exit : exit
  ; chdir : chdir
  ; env : env
  ; signal : signal
  ; time : time
  ; random : random
  ; stdin : stdin
  ; stdout : stdout
  ; stderr : stderr
  ; fs_read : fs_read
  ; fs_write : fs_write
  ; tmp : tmp
  ; network : network >
[@@alert mint "Only Ox_app and Ox_test mint a powerbox (docs/caps.md)."]
