type unavailable = {
  message : string;
  retryable : bool;
  retry_after : Eta.Duration.t option;
  status : int option;
}
(** Why no reply came, and whether another attempt is worth making: a transport failure
    is, a provider error the endpoint already answered is not. *)

type mismatch = { expected : string; got : string }
(** The model the caller asked for and the model the reply named. *)

type t =
  [ `Unavailable of unavailable
  | `Timeout
  | `Authentication of string
  | `Invalid_response of Eta_json.issue
  | `Input_too_large of Eta_json.too_large
  | `Model_mismatch of mismatch ]

let retryable = function
  | `Unavailable { retryable; _ } -> retryable
  | `Timeout -> true
  | `Authentication _ | `Invalid_response _ | `Input_too_large _ | `Model_mismatch _ ->
      false

let pp fmt = function
  | `Unavailable { message; _ } -> Format.fprintf fmt "unavailable: %s" message
  | `Timeout -> Format.pp_print_string fmt "timed out"
  | `Authentication why -> Format.fprintf fmt "authentication failed: %s" why
  | `Invalid_response issue ->
      Format.fprintf fmt "invalid response: %a" Eta_json.pp_issue issue
  | `Input_too_large { Eta_json.limit; length } ->
      Format.fprintf fmt "request is %d bytes, over the %d-byte limit" length limit
  | `Model_mismatch { expected; got } ->
      Format.fprintf fmt "model mismatch: asked for %s, the reply names %s" expected got

let to_string error = Format.asprintf "%a" pp error
