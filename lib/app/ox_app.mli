module Env = Env
(** The Door: one root Eio Switch, ordered Services, and classified exits. Cancellation
    interrupts the program and runs root-switch releases in reverse acquisition order. A
    release defect is never treated as a clean stop. *)

module Status = Status
module Config = Config

type validation_error = Config.validation_error
(** The Door's name for {!Config.validation_error}: one failure {!run}'s validator
    returns, rendered like a decode issue. *)

type telemetry = {
  reporters : Ox_observability.Logger.Reporter.t list;
      (** Where the program's records go besides the journal, in order. *)
  span_ids : (unit -> string) option;
      (** The program logger's {!Ox_observability.Logger.create} ID generator: exactly 32
          lowercase hexadecimal digits per call, as {!Ox_observability.Logger.span}
          requires. [None] keeps today's behavior — spans stay start/end records without
          trace context — and [Some] is what an exporter needs to turn them into OTLP
          spans. *)
}
(** What a telemetry hook returns to {!run} and {!run_for_test} (^napp-idii). A record
    rather than a reporter list because the span ID generator belongs to the same result:
    {!Ox_observability.Logger.create} takes both when the program's logger is built, and
    the Door must not need a second hook to supply the second half. *)

module type SERVICE = sig
  type t
  type config
  type deps
  type error

  val create : sw:Eio.Switch.t -> config -> deps -> (t, error) result
  (** Acquire against [sw]; cancellation unwinds its finalizers in reverse registration
      order. Typed failures are returned; defects propagate. *)

  val status : t -> Status.t
  (** Query current state; must not retain a snapshot at acquisition. *)
end

val status_query : (unit -> Status.t) list -> unit -> Status.t list
(** Compose status thunks into one query. Pure: it captures the thunks, reads the live
    values at call time, and neither suspends, observes cancellation, nor registers
    finalizers. A Service created before {!serve} can hold it. *)

val serve : sw:Eio.Switch.t -> unit -> ('a, 'e) result
(** Block until interrupted. The query is composed by {!status_query} and handed to
    Services as a dep before this call. [sw] is the root switch owning Services;
    cancellation releases its finalizers before the Door returns. The function never
    produces a value: it returns only by interruption, which the enclosing [Scope.run]
    classifies. A switch that has already finished is a defect. *)

val request_stop : sw:Eio.Switch.t -> Ox.Interrupt_id.t -> unit
(** Interrupt the root scope from a fiber (never directly from a signal handler). Only an
    ID passed to this function inside the Door makes a bare root interruption a clean
    exit; foreign or anonymous root cancellation exits the Door's defect exit (default 2).
    The switch runs all finalizers before the Door returns. *)

val run_for_test_with_args :
  ?on_switch:(Eio.Switch.t -> unit) ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands_with_env:('base Env.t -> (unit -> int) Cmdliner.Cmd.t list) ->
  ?commands_with_env:
    ('base Env.t ->
    ((Eio.Switch.t -> (unit, 'err) result) -> int) ->
    (unit -> int) Cmdliner.Cmd.t list) ->
  ?commands_with_env_code:
    ('base Env.t ->
    ((Eio.Switch.t -> (unit, 'err) result) -> int) ->
    ((Eio.Switch.t -> int) -> int) ->
    (unit -> int) Cmdliner.Cmd.t list) ->
  ?bare:[ `Service | `Help | `Command of 'base Env.t -> (unit -> int) Cmdliner.Term.t ] ->
  ?usage_exit:int ->
  ?exit_code:('err -> int) ->
  ?defect_exit:int ->
  ?interrupt_exit:int ->
  ?doc:string ->
  ?version:string ->
  ?man:Cmdliner.Manpage.block list ->
  ?exits:Cmdliner.Cmd.Exit.info list ->
  ?diagnostic:
    (kind:[ `Usage | `Config | `Validation | `Defect ] -> message:string -> string) ->
  ?validation_exit:int ->
  ?log_level:Ox_observability.Logger.level ->
  ?journal_level:Ox_observability.Logger.level ->
  ?service_command:string ->
  ?config_file:string ->
  ?missing:Config.missing ->
  ?decode_with_env:('base Env.t -> Yojson.Safe.t -> ('cfg, string) result) ->
  ?validate:('base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  ?validate_source:
    ('base Env.t -> Config.source -> 'cfg -> (unit, validation_error list) result) ->
  ?telemetry:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> telemetry) ->
  ?telemetry_result:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> (telemetry, 'err) result) ->
  service_args:'args Cmdliner.Term.t ->
  env:(< clock : _ Eio.Time.clock ; mono_clock : _ Eio.Time.Mono.t ; .. > as 'base) ->
  journal:Ox_observability.Logger.Reporter.t ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  getenv:(string -> string option) ->
  read:(string -> (string, Config.read_error) result) ->
  stderr:(string -> unit) ->
  stdout:(string -> unit) ->
  argv:string array ->
  ('base Env.t -> Config.source -> 'cfg -> 'args -> Eio.Switch.t -> (unit, 'err) result) ->
  int
(** Typed Door: [service_args] is parsed once, for the bare/default invocation and the
    named service command. [commands_with_env] constructs Cmdliner commands with the
    Door's pre-config Env and a [run_owned] callback. A command's parsed term may call
    [run_owned (fun sw -> ...)] to enter its own root switch, install the same signal
    monitor, classify its result, and wait for finalizers. These extra commands do not
    load config automatically: commands that need it own that choice. The Env given to the
    builder has the journal-only logger; telemetry belongs only to the service.
    [commands_with_env_code] preserves that builder unchanged while also supplying
    [run_owned_code : (Eio.Switch.t -> int) -> int]. Its task runs in a fresh
    signal-monitored switch and returns its integer only after finalizers finish. Both
    command builders may be supplied; their commands are concatenated. A requested stop
    exits [interrupt_exit] (default 130) for [run_owned_code], while the existing
    [run_owned] and the service retain their clean-stop exit 0. Foreign stops and defects
    exit [defect_exit] (default 2). [bare = `Help] makes the group print help (exit 0)
    with no service or config load; the default is [`Service]. [usage_exit] defaults to 2
    for Cmdliner parse errors; [exit_code] defaults to [(fun _ -> 1)] for typed errors of
    both the service and [run_owned]. [doc] changes the top-level help description
    (default ["Run the service."]). [validation_exit] changes the exit for config decode
    and validation rejections on both startup and config check (default 2); validator
    defects exit [defect_exit] (default 2). [log_level] sets the minimum level of both the
    pre-config journal logger and the program logger, filtering journal and telemetry
    alike (default [Info]). [journal_level] optionally filters only the journal reporter,
    including the pre-config logger; absent it, the journal has no additional filter. The
    program logger and telemetry reporters retain [log_level]. ^napp-xb3q

    ^napp-fsxf ^napp-7hvu ^napp-k9in ^napp-k0x0 ^napp-1k5x ^napp-j3qu ^napp-izjt
    Parsing/help do not enter a switch. ^napp-ytqk ^napp-x11e

    [diagnostic] transforms each complete Door diagnostic once before it is written to
    [stderr]: Cmdliner parse/usage output is [`Usage], config load/decode output is
    [`Config], validator rejections and plain typed failures are [`Validation], and other
    Cause reports are [`Defect]. [defect_exit] sets the exit for those non-Fail Causes and
    validator-raised defects (default 2); typed failures, usage errors and validation
    rejections retain their own mappings. Requested stops retain their existing exits.
    ^napp-5e3x The input includes its original final newline; the returned string is
    written verbatim (a JSON-lines renderer supplies its own newline). With no hook the
    original text is unchanged. Help, version, successful output, consumer-owned writes
    and journal records are not transformed. Renderer exceptions propagate without
    recursively invoking the hook. ^napp-5u8d ^napp-5c2v ^napp-5d7f

    [man] and [exits] are forwarded to the top-level and each Door-built service, config
    and check command info. Omitting them keeps Cmdliner's defaults; supplied exit info
    changes help, not evaluation or exit-code mapping. Consumer command infos are left
    alone. ^napp-5h4m

    [bare = `Command build] uses [build] with the pre-config Env as the default term. Its
    deferred [unit -> int] is run on a bare invocation instead of loading config or
    entering the service; its returned code is preserved. The author owns output and
    resource scopes. Help does not execute the thunk. [`Service] and [`Help] are
    unchanged. ^napp-5b9o

    [config_file] names the default XDG file (default [config.toml]); [missing] decides
    whether an absent default is decoded from an empty document or rejected. Explicit
    --config is always required. [validate_source] receives the resolved source before the
    program and on config check, so relative references can use its directory. [read] is
    the sole read seam, including config check. ^napp-ersz

    [decode_with_env], when supplied, replaces [spec.of_yojson] on every decode the Door
    performs — service start and [config check] — and receives the minted pre-config Env,
    caps included, plus the JSON value the derived decoder would have seen. [spec.env]
    still applies afterwards. A string error is a Config diagnostic with the existing
    validation exit. Omitting it uses [spec.of_yojson] unchanged. A missing required file
    is a load error and does not call the decoder. ^napp-5w6t

    [config_commands_with_env] is [config_commands] for commands that need the Door's
    pre-config {!Env} — above all its powerbox, [env.caps], the only source of
    capabilities a command has (^ncaps-0mvw). [commands_with_env] gives the top-level
    commands the same Env. The Door mints one powerbox per call and every {!Env} it builds
    carries it. *)

val run_for_test :
  ?on_switch:(Eio.Switch.t -> unit) ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?exit_code:('err -> int) ->
  ?defect_exit:int ->
  ?bare:[ `Service | `Help | `Command of 'base Env.t -> (unit -> int) Cmdliner.Term.t ] ->
  ?doc:string ->
  ?man:Cmdliner.Manpage.block list ->
  ?exits:Cmdliner.Cmd.Exit.info list ->
  ?diagnostic:
    (kind:[ `Usage | `Config | `Validation | `Defect ] -> message:string -> string) ->
  ?validation_exit:int ->
  ?log_level:Ox_observability.Logger.level ->
  ?journal_level:Ox_observability.Logger.level ->
  ?service_command:string ->
  ?config_file:string ->
  ?missing:Config.missing ->
  ?decode_with_env:('base Env.t -> Yojson.Safe.t -> ('cfg, string) result) ->
  ?validate:('base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  ?validate_source:
    ('base Env.t -> Config.source -> 'cfg -> (unit, validation_error list) result) ->
  ?telemetry:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> telemetry) ->
  ?telemetry_result:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> (telemetry, 'err) result) ->
  env:(< clock : _ Eio.Time.clock ; mono_clock : _ Eio.Time.Mono.t ; .. > as 'base) ->
  journal:Ox_observability.Logger.Reporter.t ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  getenv:(string -> string option) ->
  read:(string -> (string, Config.read_error) result) ->
  stderr:(string -> unit) ->
  stdout:(string -> unit) ->
  argv:string array ->
  ('base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) ->
  int
(** Evaluate the complete Door in the current Eio fiber without installing OS signals or
    accessing files except via [read], which reports [`Missing] for a path that is not
    there and [`Unreadable message] for one that exists and could not be read; whether
    absence is allowed is {!Config.load}'s decision. [on_switch] can initiate interruption
    via {!request_stop}. Cmdliner help is sent to [stdout], diagnostics to [stderr]. All
    switch finalizers finish before return. ^napp-9x0s

    [bare], [defect_exit], [man], [exits], [diagnostic] and [decode_with_env] have the
    same contract as {!run_for_test_with_args}. ^napp-5u8d ^napp-5c2v ^napp-5d7f
    ^napp-5h4m ^napp-5b9o ^napp-5e3x ^napp-5w6t

    [commands] are added to the top-level group; [config_commands] are added to the Door's
    own `config` group beside `check`, so a service author writes `config init` without
    rebuilding the group Cmdliner would refuse as a duplicate. A consumer subcommand
    returns its own exit code and loads no configuration. ^napp-wf22

    [service_command] is the name of the Door's own command that starts the program. It
    defaults to ["run"] and it is also the term the group evaluates when no subcommand is
    given, so a bare `<name>` starts the program under either name. A service that wants
    `run` for a verb of its own names the Door's command something else and adds that verb
    through [commands]; the name must then be free in [commands], since Cmdliner refuses
    two subcommands with one name. ^napp-d5e4

    [config] is the Door's three functions over the consumer's config type: the derived
    [of_yojson], the derived [yojson_of_t] `config check` prints, and [env], which applies
    environment overrides to the decoded value. [validate] runs after decoding and after
    those overrides, with this Door's {!Env}, and before the root switch exists. An
    [Error] list is rendered to [stderr] and returned as [validation_exit] without
    entering the program; a validator that raises is a defect, rendered with `Cause.pp`
    and exiting [defect_exit] (default 2). The `config check` path runs it too, and prints
    the redacted config only when it accepts.

    [telemetry_result] is [telemetry] for a hook whose acquisition can fail (an exporter
    that cannot be created): its [Error e] is rendered through [pp_err] with exit 1, like
    a program failure, before the program logger exists, and the program is never entered.
    Give one of the two; both raise [Invalid_argument]. ^napp-scz2

    [telemetry] runs on the run path alone — `config check` never calls it — after
    [validate] accepts, inside the root switch and before the program. It receives that
    switch, the {!Env} the validator saw, and the validated config, and returns the
    reporters and the ID generator of {!telemetry}. Its reporters are combined with
    [journal] by [Ox_observability.Logger.Reporter.tee], journal first, into the logger
    the program's {!Env} carries, and its [span_ids] is that logger's generator: the
    program's logger is the one that exports, and the hook's own {!Env} is the
    journal-only logger that exists before the hook's result does. Everything the hook
    acquires against [sw] — an exporter, a socket — is released when the program stops and
    before this function returns, so a flush registered on the switch completes first. A
    hook that raises is a defect: it is rendered with `Cause.pp` and exits [defect_exit]
    (default 2). ^napp-idii *)

val run_with_args :
  ?wakeup_ms:int ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands_with_env:
    (Eio_unix.Stdenv.base Env.t -> (unit -> int) Cmdliner.Cmd.t list) ->
  ?commands_with_env:
    (Eio_unix.Stdenv.base Env.t ->
    ((Eio.Switch.t -> (unit, 'err) result) -> int) ->
    (unit -> int) Cmdliner.Cmd.t list) ->
  ?commands_with_env_code:
    (Eio_unix.Stdenv.base Env.t ->
    ((Eio.Switch.t -> (unit, 'err) result) -> int) ->
    ((Eio.Switch.t -> int) -> int) ->
    (unit -> int) Cmdliner.Cmd.t list) ->
  ?bare:
    [ `Service
    | `Help
    | `Command of Eio_unix.Stdenv.base Env.t -> (unit -> int) Cmdliner.Term.t ] ->
  ?usage_exit:int ->
  ?exit_code:('err -> int) ->
  ?defect_exit:int ->
  ?interrupt_exit:int ->
  ?doc:string ->
  ?version:string ->
  ?man:Cmdliner.Manpage.block list ->
  ?exits:Cmdliner.Cmd.Exit.info list ->
  ?diagnostic:
    (kind:[ `Usage | `Config | `Validation | `Defect ] -> message:string -> string) ->
  ?validation_exit:int ->
  ?log_level:Ox_observability.Logger.level ->
  ?journal_level:Ox_observability.Logger.level ->
  ?service_command:string ->
  ?config_file:string ->
  ?missing:Config.missing ->
  ?decode_with_env:(Eio_unix.Stdenv.base Env.t -> Yojson.Safe.t -> ('cfg, string) result) ->
  ?read_file:(Eio_unix.Stdenv.base -> string -> (string, Config.read_error) result) ->
  ?validate:(Eio_unix.Stdenv.base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  ?validate_source:
    (Eio_unix.Stdenv.base Env.t ->
    Config.source ->
    'cfg ->
    (unit, validation_error list) result) ->
  ?telemetry:(sw:Eio.Switch.t -> Eio_unix.Stdenv.base Env.t -> 'cfg -> telemetry) ->
  ?telemetry_result:
    (sw:Eio.Switch.t -> Eio_unix.Stdenv.base Env.t -> 'cfg -> (telemetry, 'err) result) ->
  service_args:'args Cmdliner.Term.t ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  (Eio_unix.Stdenv.base Env.t ->
  Config.source ->
  'cfg ->
  'args ->
  Eio.Switch.t ->
  (unit, 'err) result) ->
  int
(** Production counterpart of {!run_for_test_with_args}. [read_file] replaces the default
    Eio filesystem reader in the service and [config check], allowing a consumer to
    enforce regular-file and byte limits using {!Config.read_regular}. Reader failures
    must distinguish [`Missing] from [`Unreadable]. The application still owns live
    reload. Its CLI options and owned-code builder match {!run_for_test_with_args}.
    [wakeup_ms] selects the same outer-scope ticker as {!run}. ^napp-ytqk ^napp-x11e
    ^napp-ersz ^napp-k0x0 ^napp-1k5x ^napp-j3qu ^napp-izjt *)

val run :
  ?wakeup_ms:int ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?exit_code:('err -> int) ->
  ?defect_exit:int ->
  ?bare:
    [ `Service
    | `Help
    | `Command of Eio_unix.Stdenv.base Env.t -> (unit -> int) Cmdliner.Term.t ] ->
  ?doc:string ->
  ?man:Cmdliner.Manpage.block list ->
  ?exits:Cmdliner.Cmd.Exit.info list ->
  ?diagnostic:
    (kind:[ `Usage | `Config | `Validation | `Defect ] -> message:string -> string) ->
  ?validation_exit:int ->
  ?log_level:Ox_observability.Logger.level ->
  ?journal_level:Ox_observability.Logger.level ->
  ?service_command:string ->
  ?config_file:string ->
  ?missing:Config.missing ->
  ?decode_with_env:(Eio_unix.Stdenv.base Env.t -> Yojson.Safe.t -> ('cfg, string) result) ->
  ?read_file:(Eio_unix.Stdenv.base -> string -> (string, Config.read_error) result) ->
  ?validate:(Eio_unix.Stdenv.base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  ?validate_source:
    (Eio_unix.Stdenv.base Env.t ->
    Config.source ->
    'cfg ->
    (unit, validation_error list) result) ->
  ?telemetry:(sw:Eio.Switch.t -> Eio_unix.Stdenv.base Env.t -> 'cfg -> telemetry) ->
  ?telemetry_result:
    (sw:Eio.Switch.t -> Eio_unix.Stdenv.base Env.t -> 'cfg -> (telemetry, 'err) result) ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  (Eio_unix.Stdenv.base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) ->
  int
(** Own Eio_main, filesystem config loading, a journal logger, and SIGINT / SIGTERM
    handlers. [bare], [defect_exit], [man], [exits], [diagnostic] and [decode_with_env]
    are forwarded unchanged, with the contracts in {!run_for_test_with_args}. ^napp-5u8d
    ^napp-5c2v ^napp-5d7f ^napp-5h4m ^napp-5b9o ^napp-5e3x ^napp-5w6t

    A config file that is absent at the default path — no --config was given — decodes as
    the empty document, so a config type with defaults starts a fresh install with no
    file; a --config path that is absent is an error naming it, and a file that exists and
    cannot be read is an error either way (^napp-9x0s). Signal handlers only set an atomic
    flag and broadcast an Eio condition; a monitor fiber requests the interruption.
    Handlers are restored after all finalizers. [validate] is forwarded to {!run_for_test}
    unchanged, so it runs on both the run and `config check` paths before the program's
    switch. [telemetry] is forwarded too, so the reporters and the ID generator it returns
    reach the program's logger, and its resources live on the root switch a signal
    interrupts. ^napp-idii

    [service_command] is forwarded as well: the Door's start command carries the name the
    service author gives it, so a program can use `run` for a verb of its own. ^napp-d5e4

    [exit_code] maps a typed failure of the program to the process's exit code (default
    [(fun _ -> 1)]): Ox's `OxApp.WithEitherErrors.handleError`. A defect, a foreign
    interruption or a release failure still exits [defect_exit] (default 2), and a stop
    the Door requested (SIGINT, SIGTERM) exits 0, Ox's default `interruptedExitCode`.
    ^nfloor-6n2e

    [wakeup_ms] selects the posix wake-up interval, ahead of [OX_POSIX_WAKEUP_MS] and the
    50 ms default. Zero disables it; negative or malformed values are rejected.
    {!Eio.Stdenv.backend_id} detects the actual backend, including automatic fallback:
    other backends never start a ticker. The service program logs the backend and
    effective interval once through its journal logger, subject to [log_level] and
    [journal_level]. Owned/client commands start the ticker silently and keep stderr
    clean. Its outer switch outlives the program's cancellation and all protected cleanup
    (^nwake-27rc, ^nwake-y4cx). *)

val posix_wakeup :
  caps:< Ox_caps.Cap.env ; .. > ->
  sw:Eio.Switch.t ->
  ?interval_ms:int ->
  ?logger:Ox_observability.Logger.t ->
  < backend_id : string
  ; clock : _ Eio.Time.clock
  ; mono_clock : _ Eio.Time.Mono.t
  ; stderr : _ Eio.Flow.sink
  ; .. > ->
  unit
(** Start a switch-owned daemon only when {!Eio.Stdenv.backend_id} is ["posix"]. Requires
    [caps] to read [OX_POSIX_WAKEUP_MS] when [interval_ms] is absent. [interval_ms]
    overrides [OX_POSIX_WAKEUP_MS]; the default is 50 ms and zero disables the daemon.
    Negative or malformed intervals raise [Invalid_argument]. When [logger] is supplied,
    log the actual backend and effective interval once through it, subject to its filters;
    other backends log an interval of zero. Without [logger], start silently and leave
    stderr untouched.

    The Door uses this on its outer switch. Callers with their own Eio runtime must
    likewise start it before the inner program/cancellation scope and close its switch
    only after that scope's protected cleanups return.

    Suspension: may suspend in the supplied logger's reporter; the daemon sleeps on
    [env#clock] independently. Cancellation: propagates from reporter calls and switch
    checks. Finalizers: [sw] owns the daemon and cancels it when the switch finishes.
    Locking: this function acquires no lock around caller code; reporter locking depends
    on the supplied logger. Cancellation safety: unsafe because progress is lost if
    cancellation interrupts reporter output; a startup record may be partially emitted.
    ^nwake-27rc ^nwake-y4cx *)

val with_powerbox : (Ox_caps.Cap.all_caps -> 'a) -> 'a
(** Mint this process's powerbox and pass it to [f]. For an entry that already owns its
    CLI and runtime, and so does not use {!run}: grip's commands stay grip's parser, and
    its OTLP worker keeps its own [Eio_main] on a systhread (^grpcap-4kdm). Does not start
    Eio, parse arguments, install signal handlers, or start a wake-up ticker. A caller
    that starts its own Eio runtime and spawns processes on posix must use {!posix_wakeup}
    on an outer switch that outlives its program's cancellation and protected cleanup.
    Call it once, from the process entry ([exit (Ox_app.with_powerbox ...)] is the entry
    form the gate allows), and pass the result down. A library does not mint. ^ncaps-0mvw
*)

val run_simple :
  ?wakeup_ms:int ->
  ?exit_code:('err -> int) ->
  ?log_level:Ox_observability.Logger.level ->
  ?journal_level:Ox_observability.Logger.level ->
  name:string ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  (Eio_unix.Stdenv.base Env.t -> Eio.Switch.t -> (unit, 'err) result) ->
  int
(** {!run} for a program with no configuration: Ox's `OxApp.Simple`. No file is read, and
    any [--config] document is decoded to [()] and ignored ({!Config.none}); the Door
    still owns Eio_main, the journal logger, SIGINT / SIGTERM, the classification of the
    program's exit and the exit code. The program receives the {!Env} and the root switch,
    on which its background fibers and resources live: they are cancelled, their releases
    run in reverse order and the Door returns only afterwards. A typed failure exits
    through [exit_code] (default 1); a defect is rendered as a full [Cause] on stderr and
    exits 2 where Ox's [Simple] prints a stack trace and exits 1, so that a defect can be
    told from a typed failure. [wakeup_ms] follows the selection and outer-scope lifetime
    of {!run}. ^nfloor-6n2e *)
