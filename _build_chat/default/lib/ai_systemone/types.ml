(* The System One derived wire types: exactly the shapes `reference/jev.ts` names and
   `reference/model.py` (jev-ultrafast 1231850a) builds. Every type here carries
   [@@deriving yojson] (ADR-0008: types are the schema), so the decoder the client runs is
   the one this declaration describes.

   Two things the deriver cannot shape live in {!Codecs} beside these types: a variant
   whose wire form is one object with a `type` field (the deriver writes `[tag, payload]`
   arrays), and a record member that is a JSON object (an association list encodes as an
   array of pairs). Everything a caller constructs or reads is a type here.

   Raw JSON stays [Yojson.Safe.t]: `state` and `instructions` are the caller's document,
   and a criterion's value is whatever the caller offers (`null` when it offers nothing,
   as `reference/jev.ts` spells it), so no OCaml type may narrow them. ^nso-jz8v *)

type 'value map = (string * 'value) list
(** A string-keyed map, on the wire a JSON object. `Codecs.t_of_map` accepts an object or
    the array-of-pairs form an OCaml association list would encode as, so a decoder never
    refuses a shape its own encoder can write. *)

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
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** Token usage and cost the provider reports; all three are required, so a reply without
    them is refused rather than read as zero. *)

type choice_question = { instructions : Yojson.Safe.t; criteria : Yojson.Safe.t map }
(** A choice question: raw `instructions` and criteria keyed by the option's key, each
    with its value or nothing. This is the shape jev-ultrafast builds in `model.py`, where
    `instructions` is [{"goal": ..., "rules": ...}] and a criterion is an object or
    `null`; `reference/jev.ts` spells the value `string | null`, so anything narrower than
    raw JSON would refuse a request JEV was trained on. *)

type score_question = { instructions : Yojson.Safe.t; levels : string list }
(** A score question: raw `instructions` and the levels in order, on the wire under the
    key ["criteria"]. *)
