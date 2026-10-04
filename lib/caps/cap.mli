(** Capabilities: a function's type says what it may touch (^ncaps-sojd).

    A capability is an object with one method whose result type is an abstract token, so
    the only way to hold one is to be handed it: the Door mints the one powerbox of a
    process ([Ox_caps_door.powerbox], ^ncaps-0mvw ^ncaps-uiq6), a program narrows it by
    type ascription ([(env.caps :> < Cap.fork; Cap.exec >)]) and passes each service
    exactly the capabilities it names. A function that may fork and exec says so:
    [val launch : caps:< Cap.fork; Cap.exec; .. > -> ...]. The row variable [..] lets a
    wider powerbox be passed as it is, and the body can use only the methods the type
    lists.

    Capabilities cover what Eio does not already hand out as values (^ncaps-jkku): Eio's
    [net], [fs], [process_mgr], [clock] and [domain_mgr] stay Eio values passed as they
    are. The dangerous standard-library calls live behind {!Cap_unix}, {!Cap_sys} and
    {!Cap_stdlib}, and the compiler-backed [ox-caps-*] rules forbid the raw calls
    everywhere else (^ncaps-n6r0).

    A capability is a single-domain value (^ncaps-vlwm): objects are not [portable] across
    OxCaml domains, which is why v1 dropped object capabilities. A future parallel package
    that crosses domains mints a powerbox per domain inside its Door; it never ships one
    across. Capabilities own no resource, never suspend and are not affected by
    cancellation. *)

(** The abstract results of the capability methods. Their representations are sealed in
    [ox_caps.door]: a capability cannot be forged by writing an object with the same
    method names (^ncaps-aw5n ^ncaps-uiq6). *)
module Token : sig
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
(** Start another program: what spawning a child needs. *)

type console = < stdin ; stdout ; stderr >
(** The process's standard streams. *)

type fs = < fs_read ; fs_write ; tmp >
(** The filesystem outside Eio's [fs]. *)

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
(** Every capability: what the Door's powerbox holds. *)

type no_caps = < >
(** A function that takes [no_caps] states that it touches nothing. *)
