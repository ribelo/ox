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
  reporters : Eta_observability.Logger.Reporter.t list;
      (** Where the program's records go besides the journal, in order. *)
  span_ids : (unit -> string) option;
      (** The program logger's {!Eta_observability.Logger.create} ID generator: exactly 32
          lowercase hexadecimal digits per call, as {!Eta_observability.Logger.span}
          requires. [None] keeps today's behavior — spans stay start/end records without
          trace context — and [Some] is what an exporter needs to turn them into OTLP
          spans. *)
}
(** What a telemetry hook returns to {!run} and {!run_for_test} (^napp-idii). A record
    rather than a reporter list because the span ID generator belongs to the same result:
    {!Eta_observability.Logger.create} takes both when the program's logger is built, and
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

val request_stop : sw:Eio.Switch.t -> Eta.Interrupt_id.t -> unit
(** Interrupt the root scope from a fiber (never directly from a signal handler). Only an
    ID passed to this function inside the Door makes a bare root interruption a clean
    exit; foreign or anonymous root cancellation exits 2. The switch runs all finalizers
    before the Door returns. *)

val run_for_test :
  ?on_switch:(Eio.Switch.t -> unit) ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?service_command:string ->
  ?validate:('base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  ?telemetry:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> telemetry) ->
  env:(< clock : _ Eio.Time.clock ; mono_clock : _ Eio.Time.Mono.t ; .. > as 'base) ->
  journal:Eta_observability.Logger.Reporter.t ->
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
    [Error] list is rendered to [stderr] and returned as exit 2 without entering the
    program; a validator that raises is a defect, rendered with `Cause.pp` and also
    exiting 2. The `config check` path runs it too, and prints the redacted config only
    when it accepts.

    [telemetry] runs on the run path alone — `config check` never calls it — after
    [validate] accepts, inside the root switch and before the program. It receives that
    switch, the {!Env} the validator saw, and the validated config, and returns the
    reporters and the ID generator of {!telemetry}. Its reporters are combined with
    [journal] by [Eta_observability.Logger.Reporter.tee], journal first, into the logger
    the program's {!Env} carries, and its [span_ids] is that logger's generator: the
    program's logger is the one that exports, and the hook's own {!Env} is the
    journal-only logger that exists before the hook's result does. Everything the hook
    acquires against [sw] — an exporter, a socket — is released when the program stops and
    before this function returns, so a flush registered on the switch completes first. A
    hook that raises is a defect: it is rendered with `Cause.pp` and exits 2. ^napp-idii
*)

val run :
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?config_commands:(unit -> int) Cmdliner.Cmd.t list ->
  ?service_command:string ->
  ?validate:(Eio_unix.Stdenv.base Env.t -> 'cfg -> (unit, validation_error list) result) ->
  ?telemetry:(sw:Eio.Switch.t -> Eio_unix.Stdenv.base Env.t -> 'cfg -> telemetry) ->
  name:string ->
  config:'cfg Config.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  (Eio_unix.Stdenv.base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) ->
  int
(** Own Eio_main, filesystem config loading, a journal logger, and SIGINT / SIGTERM
    handlers. A config file that is absent at the default path — no --config was given —
    decodes as the empty document, so a config type with defaults starts a fresh install
    with no file; a --config path that is absent is an error naming it, and a file that
    exists and cannot be read is an error either way (^napp-9x0s). Signal handlers only
    set an atomic flag and broadcast an Eio condition; a monitor fiber requests the
    interruption. Handlers are restored after all finalizers. [validate] is forwarded to
    {!run_for_test} unchanged, so it runs on both the run and `config check` paths before
    the program's switch. [telemetry] is forwarded too, so the reporters and the ID
    generator it returns reach the program's logger, and its resources live on the root
    switch a signal interrupts. ^napp-idii

    [service_command] is forwarded as well: the Door's start command carries the name the
    service author gives it, so a program can use `run` for a verb of its own. ^napp-d5e4
*)
