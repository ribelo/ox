(** The Door: one root Eio Switch, ordered Services, and classified exits.
    Cancellation interrupts the program and runs root-switch releases in reverse
    acquisition order. A release defect is never treated as a clean stop. *)
module Env = Env
module Status = Status
module Config = Config

module type SERVICE = sig
  type t
  type config
  type deps
  type error
  val create : sw:Eio.Switch.t -> config -> deps -> (t, error) result
  (** Acquire against [sw]; cancellation unwinds its finalizers in reverse
      registration order. Typed failures are returned; defects propagate. *)
  val status : t -> Status.t
  (** Query current state; must not retain a snapshot at acquisition. *)
end

val serve : sw:Eio.Switch.t -> publish:((unit -> Status.t list) -> unit) -> (unit -> Status.t) list -> ('a, 'e) result
(** Publish a live status query and block until interrupted. [sw] is the root
    switch owning Services; cancellation releases its finalizers before the
    Door returns. The query is valid only while the program runs. *)
val request_stop : sw:Eio.Switch.t -> Eta.Interrupt_id.t -> unit
(** Interrupt the root scope from a fiber (never directly from a signal
    handler). Only an ID passed to this function inside the Door makes a bare
    root interruption a clean exit; foreign or anonymous root cancellation
    exits 2. The switch runs all finalizers before the Door returns. *)

val run_for_test :
  ?on_switch:(Eio.Switch.t -> unit) ->
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  env:(< clock : _ Eio.Time.clock; mono_clock : _ Eio.Time.Mono.t; .. > as 'base) ->
  journal:Eta_observability.Logger.Reporter.t ->
  name:string -> config:'cfg Eta_schema.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  getenv:(string -> string option) ->
  read:(string -> (string, string) result) ->
  stderr:(string -> unit) -> stdout:(string -> unit) ->
  argv:string array ->
  ('base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) -> int
(** Evaluate the complete Door in the current Eio fiber without installing
    OS signals or accessing files except via [read]. [on_switch] can initiate
    interruption via {!request_stop}. Cmdliner help is sent to [stdout],
    diagnostics to [stderr]. All switch finalizers finish before return. *)

val run :
  ?commands:(unit -> int) Cmdliner.Cmd.t list ->
  name:string -> config:'cfg Eta_schema.t ->
  pp_err:(Format.formatter -> 'err -> unit) ->
  (Eio_unix.Stdenv.base Env.t -> 'cfg -> Eio.Switch.t -> (unit, 'err) result) -> int
(** Own Eio_main, filesystem config loading, a journal logger, and SIGINT /
    SIGTERM handlers. Signal handlers only set an atomic flag and broadcast an
    Eio condition; a monitor fiber requests the interruption. Handlers are
    restored after all finalizers. *)
