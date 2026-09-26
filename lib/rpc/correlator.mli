(** Scoped request/reply correlation over complete, opaque messages. The caller owns
    framing and transport lifetime. [create] owns one reader fiber on [sw]; [close]
    cancels and joins it. Switch teardown cancels it and settles callers. Cancellation of
    a call propagates and removes its pending slot; there is no RPC-level cancellation
    message. No transport finalizer is installed. *)

type close_reason = [ `Eof | `Read_failed of exn | `Closed ]

type error =
  [ `Transport_closed of close_reason | `Write_failed of exn | `Timeout | `Id_exhausted ]

type stats = { pending : int; buffered_notifications : int; dropped_notifications : int }
type 'msg notification = Message of 'msg | Closed of close_reason
type 'msg t

val create :
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  ?max_notifications:int ->
  read:(unit -> 'msg option) ->
  write:('msg -> unit) ->
  id:('msg -> int option) ->
  set_id:('msg -> int -> 'msg) ->
  ?session:('msg -> string option) ->
  unit ->
  'msg t
(** [read] returns [None] on EOF; read failures close all pending calls with
    [`Read_failed exn]. [write] may raise; a write failure affects only that call.
    [max_notifications] defaults to 1024 and must be positive. Notifications overflow by
    dropping the oldest and incrementing [stats]. The reader observes Eio cancellation and
    stops on switch teardown; no underlying transport is closed by this module. *)

val call :
  'msg t -> ?session:string -> ?deadline:Eta.Duration.t -> 'msg -> ('msg, error) result
(** Registers before writing; [session] overrides the session extracted from the outgoing
    message for reply matching. Concurrent writes are serialized, never retried.
    [deadline] covers writing and awaiting a reply and uses the clock supplied at
    [create]. Timeout and external cancellation remove the slot; the latter propagates as
    interruption. No finalizers are installed. *)

val notifications : 'msg t -> 'msg notification Eio.Stream.t
(** Bounded FIFO for unmatched, duplicate and late messages. Consumers may suspend in
    [Eio.Stream.take], which observes cancellation. A slow consumer loses oldest messages,
    counted in [stats]. [Closed reason] is delivered exactly once, last, for EOF, read
    failure, explicit close or switch teardown; consumers stop at [Closed]. No finalizer.
*)

val stats : 'msg t -> stats
(** Snapshot of counters; does not suspend or install finalizers. *)

val close : 'msg t -> unit
(** Idempotently reject new calls, settle all pending calls with
    [`Transport_closed `Closed], stop and join the reader before returning. Cancelling
    [close] propagates; switch teardown still joins the reader. The borrowed read/write
    transport is not finalized. *)
