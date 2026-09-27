(** The two System One wire unions, the reply and the request built from them, and the
    readers a caller asks of an answer.

    On the wire an answer and a question are each one object whose `type` field decides
    which kind it is. The deriver writes `[tag, payload]` arrays for a variant, so these
    two are shaped by hand; every field inside them is derived in {!Types}. A reply whose
    `type` is neither `"choice"` nor `"score"`, whose named member is missing, or whose
    field is of the wrong shape is refused with the path — never defaulted.

    Cancellation and finalizers: every function in this module is pure and synchronous.
    None performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards.

    ^nso-megl *)

type 'value map = (string * 'value) list
(** A string-keyed map, on the wire a JSON object. {!t_of_map} reads it. *)

type answer =
  | Choice of Types.choice_answer
  | Score of Types.score_answer  (** Any answer the client accepts. *)

type question =
  | Choice_question of Types.choice_question
  | Score_question of Types.score_question  (** Any question the client may send. *)

type response = {
  model : string;  (** the model that answered *)
  answers : (string * answer) list;  (** every named answer, in the reply's order *)
  usage : Types.usage;
  id : string option;
  provider : string option;
}
(** The whole reply. `model`, `answers` and `usage` are required; `id` and `provider` may
    be absent or null and are then [None]. *)

type request = {
  model : string;
  state : Yojson.Safe.t;
  questions : (string * question) list;
}
(** The request body, built by {!Client.evaluate} and read by the tests. *)

val t_of_map : string -> Yojson.Safe.t -> ((string * Yojson.Safe.t) list, string) result
(** [t_of_map path json] reads a JSON object as an association list, or an array of
    [key, value] pairs, and reports [path] when it is neither. Pure. *)

val map_of_pairs : (string * Yojson.Safe.t) list -> Yojson.Safe.t
(** [map_of_pairs pairs] is the JSON object of [pairs] in order. Pure. *)

val t_of_choice_answer : Yojson.Safe.t -> (Types.choice_answer, string) result

val t_of_score_answer : Yojson.Safe.t -> (Types.score_answer, string) result
(** The two answer records, read with their map members. Fail-closed: a missing or wrongly
    typed field is an [Error] naming the path, never a default. Pure. *)

val t_of_choice_question : Yojson.Safe.t -> (Types.choice_question, string) result

val t_of_score_question : Yojson.Safe.t -> (Types.score_question, string) result
(** The two question records, read with `criteria` as the JSON object the contract
    specifies. Fail-closed: a missing or wrongly typed field is an [Error] naming the
    path. Pure. *)

val choice : instructions:Yojson.Safe.t -> criteria:Yojson.Safe.t map -> question
(** [choice ~instructions ~criteria] is one choice question. *)

val score : instructions:Yojson.Safe.t -> criteria:string list -> question
(** [score ~instructions ~criteria] is one score question. *)

val question_name : question -> string
(** [question_name question] is the discriminant the request writes: ["choice"] or
    ["score"]. Pure. *)

val probability : string -> Types.choice_answer -> float option
(** [probability key answer] is the probability of [key] when the distribution names it
    and [None] otherwise. *)

val level : string -> Types.score_answer -> string option
(** [level key answer] is the legend text for [key] when the answer carries a legend and
    names it, and [None] otherwise. *)

val choice_answer_valid : Types.choice_answer -> bool
(** [choice_answer_valid answer] is the check jev-ultrafast runs before it acts
    (`reference/model.py`, `validate_choice`): every probability and the confidence is
    finite and in [0, 1], the distribution sums to 1 within 0.02, and the chosen key has
    the highest probability (ties allowed within 1e-6). The client does not run it — what
    a distribution has to look like is the caller's decision — but the rule is the
    reference's, so a caller can apply exactly it. Pure. *)

val yojson_of_answer : answer -> Yojson.Safe.t
val yojson_of_question : question -> Yojson.Safe.t
val yojson_of_response : response -> Yojson.Safe.t

val yojson_of_request : request -> Yojson.Safe.t
(** The encoders. A question's `type` field leads its object, as the reference writes it.
*)

val t_of_answer : Yojson.Safe.t -> (answer, string) result
val t_of_question : Yojson.Safe.t -> (question, string) result
val t_of_response : Yojson.Safe.t -> (response, string) result

val t_of_request : Yojson.Safe.t -> (request, string) result
(** The decoders, fail-closed: a missing required field, a wrong shape, an unknown
    discriminant or a member the type does not name is an [Error] naming the path, never a
    default. *)

val response_of_yojson : Yojson.Safe.t -> (response, string) result
(** [response_of_yojson] is {!t_of_response}, under the name a derived codec would have.
*)
