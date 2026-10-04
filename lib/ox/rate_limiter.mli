(** Rate limiting after Ox's [RateLimiter], computed on demand from an injected clock: a
    limiter has no background fiber, so nothing is left running when the last user is gone
    and a mock clock makes every algorithm deterministic.

    A limiter owns no switch, fiber or finalizer. {!run} suspends by sleeping on the
    clock, which is promptly cancellable; a fiber cancelled while it waits has consumed no
    permit. Permits are granted when the algorithm says so, not in arrival order: two
    fibers waiting for the same instant are served in whichever order they wake. The
    limiter belongs to one domain, like every Eio value it uses. *)

type verdict =
  | Granted  (** A permit was consumed; the operation may start. *)
  | Wait of Duration.t
      (** No permit now; ask again after this long (at least 1 ms). Nothing was consumed. *)

type algorithm = { try_acquire : now_ms:int -> verdict }
(** The whole interface of a rate-limiting algorithm (^nfloor-ygtz): given the clock's
    current time in milliseconds, either consume one permit and say [Granted], or say how
    long to wait. It is a stateful record — each call may change the algorithm's counters —
    and it is only ever called under the limiter's lock, never re-entrantly, and must not
    suspend. Time never runs backwards for one limiter. *)

type config =
  | Fixed_window of { n : int; per : Duration.t }
      (** At most [n] operations start in each window of length [per]; windows are
          aligned to the moment the limiter is created (Ox's [fixedWindowWithStartTime]). *)
  | Sliding_window of { n : int; per : Duration.t }
      (** At most [n] operations start in any interval of length [per]
          ([slidingWindowWithStartTime]). *)
  | Token_bucket of { capacity : int; per : Duration.t }
      (** A bucket that starts full with [capacity] tokens, gains one token every [per]
          and never holds more than [capacity] ([leakyBucket]): bursts of [capacity], then
          one operation per [per]. *)
  | Custom of (now_ms:int -> algorithm)
      (** A caller-supplied algorithm, built once with the clock's time at creation, so a
          config value can be shared without sharing state. *)

type t

val create : sw:Eio.Switch.t -> clock:_ Eio.Time.clock -> config -> t
(** [create ~sw ~clock config] starts the limiter's algorithm at the clock's current time.
    [sw] is the caller's switch and is only checked ([Invalid_argument] if it finished, the
    cancellation if it was cancelled): the limiter owns nothing on it.

    Suspension: may suspend in the caller's Custom constructor; Eio.Time.now reads
    the clock without waiting; delegated Stdlib, Stdlib.Float, Stdlib.Queue operations retain their own behaviour. Cancellation: propagates from the switch check and
    depends on the Custom callback; delegated Stdlib, Stdlib.Float, Stdlib.Queue operations retain their own behaviour. Finalizers: none are registered. Locking: no lock
    is held around the Custom constructor. Cancellation safety: unsafe because
    progress is lost if a Custom constructor is interrupted after producing effects.
    ^nlintd-a7oq

    @raise Invalid_argument if a window has [n < 1], a bucket [capacity < 1], or [per] is
    zero. ^nfloor-p4ae *)

val run : t -> (unit -> 'a) @ local -> 'a
(** [run t f] blocks until the algorithm grants a permit, then runs [f] in the calling
    fiber and returns its result, whatever it is: a [result] passes through unchanged,
    and an exception from [f] propagates. The permit is consumed before [f] starts and is
    not given back. ^nfloor-p4ae *)

val run_or_drop : t -> (unit -> 'a) @ local -> 'a option
(** [run_or_drop t f] is [Some (f ())] if a permit is available now and [None], without
    waiting or running [f], otherwise. ^nfloor-p4ae *)
