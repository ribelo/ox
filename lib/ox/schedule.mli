@@ portable

(** Pure recurrence policies copied from v1. Stepping does not suspend, observe
    cancellation, or register finalizers. *)

type ('input, 'output) t
(** A schedule consumes values of ['input] and produces ['output] values while deciding
    whether to continue and how long to wait before the next step. *)

type ('input, 'output) metadata = {
  input : 'input;
  output : 'output;
  attempt : int;
  start_ms : int;
  now_ms : int;
  elapsed : Duration.t;
  elapsed_since_previous : Duration.t;
  delay : Duration.t;
}
(** Metadata for a completed schedule step. [delay] is the sleep before the next
    recurrence when the decision is [Continue]; it is [Duration.zero] for [Done].
    [elapsed] is from the first step's clock to [now_ms]; [elapsed_since_previous] is from
    the previous step. Both are [Duration.zero] when the clock did not move forward, and
    saturate at [Duration.ms max_int] when a forward difference exceeds that range. *)

type ('input, 'output) decision =
  | Continue of ('input, 'output) metadata
  | Done of ('input, 'output) metadata

type ('left, 'right) and_then_output =
  | First_phase of 'left
  | Second_phase of 'right
      (** Output produced by {!and_then}; first-phase steps are wrapped in [First_phase],
          and second-phase steps are wrapped in [Second_phase]. *)

val recurs : int -> ('input, int) t
(** [recurs n] emits exactly [n] [Continue] steps then [Done], for [0 <= n < max_int].
    Negative [n] is treated as [0]. [n = max_int] is rejected because the mandatory
    terminal step would wrap the attempt ordinal.
    @raise Invalid_argument if [n] is [max_int]. *)

val forever : ('input, int) t
val spaced : Duration.t -> ('input, int) t
val fixed : Duration.t -> ('input, int) t
val windowed : Duration.t -> ('input, int) t

val exponential : ?factor:float -> Duration.t -> ('input, Duration.t) t
(** [exponential ~factor initial] delays [initial] times [factor] to the power of the step
    index. [factor] must be finite and nonnegative and defaults to [2]. Positive overflow
    saturates to [Duration.ms max_int]. A zero [initial] remains zero even if an
    intermediate power overflows. The growth index is still a representable ordinal:
    wrapping it is [Invalid_argument], not a delay restart.
    @raise Invalid_argument if [factor] is non-finite or negative. *)

val fibonacci : Duration.t -> ('input, Duration.t) t
val linear : initial:Duration.t -> step:Duration.t -> ('input, Duration.t) t
val elapsed : ('input, Duration.t) t
val during : Duration.t -> ('input, Duration.t) t
val recur_until : ('input -> bool) -> ('input, 'input) t
val both : ('input, 'a) t -> ('input, 'b) t -> ('input, 'a * 'b) t
val either : ('input, 'a) t -> ('input, 'b) t -> ('input, 'a * 'b) t

val and_then :
  ('input, 'left) t -> ('input, 'right) t -> ('input, ('left, 'right) and_then_output) t

val modify_delay :
  ('output -> Duration.t -> Duration.t) -> ('input, 'output) t -> ('input, 'output) t

val while_output : ('output -> bool) -> ('input, 'output) t -> ('input, 'output) t

type jitter =
  | Full  (** a uniform draw in [[0, delay]] *)
  | Equal  (** [delay / 2] plus a uniform draw in [[0, delay / 2]] *)
  | Decorrelated
      (** a uniform draw in [[base, 3 * previous]], where [base] is the first delay the inner
          schedule produced and [previous] is the last delay this jitter produced (initially
          [base]); the inner schedule's later delays are ignored, so cap the result with
          {!max_interval} *)
(** Ox's jitter kinds (the ones of the AWS backoff article). *)

val jittered :
  ?kind:jitter -> ?min:float -> ?max:float -> ('input, 'output) t -> ('input, 'output) t
(** [jittered ~min ~max schedule] multiplies each continue delay by a draw in
    [[min, max]]. Bounds must be finite, nonnegative, and [min <= max]; defaults are [0.8]
    and [1.2]. Equal bounds are valid. [jittered ~kind schedule] instead applies one of
    Ox's {!jitter} kinds to each continue delay; [~kind] excludes [~min] and [~max].
    Construction does not step the inner schedule or draw randomness.
    @raise Invalid_argument if a bound is non-finite, negative, or reversed, or if [~kind]
    is combined with [~min] or [~max]. *)

val decorrelated_jitter : min:Duration.t -> max:Duration.t -> ('input, Duration.t) t
(** Ox's [decorrelatedJitter]: forever, each delay is a uniform draw in
    [[min, 3 * previous]] capped at [max], starting from [previous = min]; the output is
    the delay. Combine with {!recurs} through {!both} to bound the attempts.
    @raise Invalid_argument if [min > max]. *)

val max_interval : Duration.t -> ('input, 'output) t -> ('input, 'output) t
(** Caps every continue delay at the given duration. *)

val with_initial_delay : Duration.t -> ('input, 'output) t -> ('input, 'output) t
(** Replaces the delay of the first recurrence (the first continue step) with the given
    one; later delays are unchanged. *)

val with_no_initial_delay : ('input, 'output) t -> ('input, 'output) t
(** [with_initial_delay Duration.zero]: the first recurrence follows immediately. *)

val intervals : Duration.t list -> ('input, Duration.t) t
(** Explicit delays: one continue step per element, in order, each delaying by that
    element and outputting it, then [Done] (with output [Duration.zero]). [intervals []]
    is done at once. *)

val max_retries_by_cumulative_delay :
  Duration.t -> ('input, 'output) t -> ('input, 'output) t
(** Ends the schedule at the first continue step whose delay would bring the sum of all
    delays granted so far above the given duration; that step becomes [Done] and its delay
    is not granted. *)

val named : string -> ('input, 'output) t -> ('input, 'output) t
(** Attach a label used by {!pp}. Naming does not change stepping and does not itself emit
    logs, spans, or metrics. *)

val pp : Format.formatter -> ('input, 'output) t -> unit

type ('input, 'output) driver

val start : ?random:Random.State.t -> ('input, 'output) t -> ('input, 'output) driver
(** Start a stateful schedule driver. [Jittered] draws from the optional Stdlib random
    state; without one, a fresh state is created. No sleeps, cancellation, or finalizers
    are involved. *)

val step :
  now_ms:int ->
  input:'input ->
  ('input, 'output) driver ->
  ('input, 'output) decision * ('input, 'output) driver
(** Step a schedule using the supplied current runtime clock and input value.

    Attempt, output-count and growth-index ordinals share one representable [int] domain.
    Advancing a leaf past [max_int] raises [Invalid_argument] before that leaf's callback
    or jitter draw. Frozen [Done] snapshots and [and_then] phase-local resets are
    unchanged. Overflow is not silently saturated, restarted, or turned into [Done]. *)

val next :
  now_ms:int ->
  input:'input ->
  ('input, 'output) driver ->
  (('input, 'output) metadata * ('input, 'output) driver) option
(** Step a schedule and return [Some metadata] only when it continues. This is a
    convenience for callers that only need recurrence delays; use {!step} when the final
    [Done] output matters. *)
