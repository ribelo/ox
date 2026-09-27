(** The System One derived wire types.

    These are exactly the shapes `reference/jev.ts` names and `reference/model.py`
    (jev-ultrafast 1231850a) builds, so the codecs {!Codecs} reads and writes are the
    contract's own. Raw JSON stays [Yojson.Safe.t]: `state` and `instructions` are the
    caller's document, and a criterion's value is whatever the caller offers (`null` when
    it offers nothing, as `reference/jev.ts` spells it), so no OCaml type narrows them.

    Cancellation and finalizers: every type here is plain data and every derived codec is
    pure and synchronous. Decoding suspends on nothing, forks no fiber and registers no
    finalizer.

    ^nso-jz8v *)

type 'value map = (string * 'value) list
(** A string-keyed map, on the wire a JSON object. *)

type choice_answer = { choice : string; probabilities : float map; confidence : float }
(** One choice answer: the selected key, its distribution and the model's confidence. *)

type score_answer = {
  score : float;
  legend : string map option;
  probabilities : float map;
  confidence : float;
}
(** One score answer: the position on the question's levels, the distribution, the
    confidence, and the legend the API keys by level index when it sends one. *)

type usage = { input_tokens : int; output_tokens : int; cost : float }
(** Token usage and cost; all three are required, so a reply without them is refused
    rather than read as zero. *)

type choice_question = { instructions : Yojson.Safe.t; criteria : Yojson.Safe.t map }
(** A choice question: raw `instructions` and criteria keyed by the option's key, each
    with its value or nothing. *)

type score_question = { instructions : Yojson.Safe.t; levels : string list }
(** A score question: raw `instructions` and the levels in order, on the wire under the
    key ["criteria"]. *)

val yojson_of_usage : usage -> Yojson.Safe.t

val usage_of_yojson : Yojson.Safe.t -> (usage, string) result
(** The derived codecs. A record decoder refuses a member the type does not name, and the
    error text carries the dotted path of the offending value. *)
