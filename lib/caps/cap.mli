(** Capabilities: a function's type says what it may touch (^ncaps-sojd).

    A capability is an object with one method whose result type is an abstract token, so
    the only way to hold one is to be handed it: the Door mints the one powerbox of a
    process ({!powerbox}, ^ncaps-0mvw), a program narrows it by type ascription
    ([(env.caps :> < Cap.fork; Cap.exec >)]) and passes each service exactly the
    capabilities it names. A function that may fork and exec says so:
    [val launch : caps:< Cap.fork; Cap.exec; .. > -> ...]. The row variable [..] lets a
    wider powerbox be passed as it is, and the body can use only the methods the type
    lists.

    Capabilities cover what Eio does not already hand out as values (^ncaps-jkku): Eio's
    [net], [fs], [process_mgr], [clock] and [domain_mgr] stay Eio values passed as they
    are. The dangerous standard-library calls live behind {!Cap_unix}, {!Cap_sys} and
    {!Cap_stdlib}, and the Semgrep rules in [caps.yaml] forbid the raw calls everywhere
    else (^ncaps-n6r0).

    A capability is a single-domain value (^ncaps-vlwm): objects are not [portable] across
    OxCaml domains, which is why v1 dropped object capabilities. A future parallel package
    that crosses domains mints a powerbox per domain inside its Door; it never ships one
    across. Capabilities own no resource, never suspend and are not affected by
    cancellation. *)

(** The abstract results of the capability methods. They have no constructor outside this
    library: a capability cannot be forged by writing an object with the same method names
    (^ncaps-aw5n). *)
module Token : sig
  type fork
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

val powerbox : unit -> all_caps
[@@alert
  mint
    "Only the Door (Ox_app) and Ox_test mint a powerbox; library and service code \
     receives capabilities as arguments (docs/caps.md)."]
(** Mint a powerbox. The Door calls it once per process and hands the result to the
    program in [Ox_app.Env.t]; [Ox_test.powerbox] is the test entry. Everywhere else the
    call is refused by the [ox-caps-mint] Semgrep rule and reported by the [mint] alert
    (^ncaps-0mvw). *)
