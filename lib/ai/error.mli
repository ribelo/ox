(** The typed failures every AI client shares.

    The set is the client contract, not a per-call accident: a caller that handles these
    six cases handles every failure the transport and the two clients can produce, and
    {!retryable} answers whether another attempt is worth making. The reference adapter
    ([reference/jev.ts]) carries the same six codes and the same retry verdicts; the two
    forms it gives [UNAVAILABLE] are {!unavailable.retryable} here.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards.

    ^nso-77t7 *)

type unavailable = {
  message : string;
  retryable : bool;
  retry_after : Ox.Duration.t option;
  status : int option;
}
(** Why no reply came, and whether another attempt is worth making: [true] for a transport
    failure or a 429/529 that ran out of attempts, [false] for an error the endpoint
    itself answered. *)

type mismatch = { expected : string; got : string }
(** The model the caller asked for and the model the reply named. *)

type t =
  [ `Unavailable of unavailable
  | `Timeout
  | `Authentication of string
  | `Invalid_response of Ox_json.issue
  | `Input_too_large of Ox_json.too_large
  | `Model_mismatch of mismatch ]
(** What went wrong:
    - [`Unavailable failure] — the attempt could not produce a reply, or an HTTP status
      the client cannot use as an answer; [failure.message] says which,
      [failure.retryable] whether another attempt is reasonable, and [failure.retry_after]
      the delay the provider asked for in [Retry-After], so a caller that schedules its
      own retries waits as told, and [failure.status] the HTTP status when the endpoint
      answered one ([None] for a transport failure), so a caller can classify statuses
      itself. ^nai-rjkq ^nai-8s4k
    - [`Timeout] — the caller's deadline passed, or an attempt's own transport slice did.
    - [`Authentication why] — the endpoint refused the key (HTTP 401).
    - [`Invalid_response issue] — bytes arrived that are not the documented reply; the
      issue carries the path of the offending value and the value itself.
    - [`Input_too_large bound] — the request is over [bound.limit] bytes ([bound.length]
      of them) and was not sent, or the endpoint refused it as too large.
    - [`Model_mismatch { expected; got }] — the reply names another model than the one
      asked for, so it is not this model's answer. *)

val retryable : [< t ] -> bool
(** [retryable error] is [true] only when another attempt could plausibly succeed:
    [`Timeout] and an [`Unavailable] that says so. Everything the caller can fix, and
    every answer the provider already gave, is [false]. *)

val pp : Format.formatter -> [< t ] -> unit
(** [pp fmt error] renders the failure as one line of text. The [`Invalid_response] case
    renders through {!Ox_json.pp_issue}, which bounds the offending subtree, so the
    rendered width is bounded. *)

val to_string : [< t ] -> string
(** [to_string error] is the text {!pp} renders. *)
