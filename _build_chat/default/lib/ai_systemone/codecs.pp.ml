(* The shapes the deriver cannot express, and the readers a caller asks of an answer.

   Three shapes need help here and the reason is the same each time. On the wire an answer
   and a question are one object whose `type` field decides which kind it is, while the
   deriver's variant form is a `[tag, payload]` array; and `probabilities` and `legend`
   are JSON objects, while an OCaml association list encodes as an array of pairs.
   Everything else — every scalar field, the questions, usage, the reply's and the
   request's members — is derived in {!Types}, so no field name is written twice.

   Cancellation and finalizers: every function in this module is pure and synchronous.
   None performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
   interrupted and nothing is released afterwards. *)

type 'value map = (string * 'value) list
(** A string-keyed map, on the wire a JSON object. A map carried inside a record is
    [Types.'value map]; this alias names the same type here because {!t_of_map} and
    {!map_of_pairs} are the functions that read and write it. *)

(** Any answer the client accepts. *)
type answer = Choice of Types.choice_answer | Score of Types.score_answer

(** Any question the client may send. *)
type question =
  | Choice_question of Types.choice_question
  | Score_question of Types.score_question

type response = {
  model : string;
  answers : (string * answer) list;
  usage : Types.usage;
  id : string option;
  provider : string option;
}
(** The whole reply: the model that answered, every named answer, the token usage and
    cost, and the optional request id and provider OpenRouter adds. *)

type request = {
  model : string;
  state : Yojson.Safe.t;
  questions : (string * question) list;
}
(** The request body: the model, the caller's state, and the named questions. *)

(** {1 Reading JSON} *)

let t_of_map path json =
  match json with
  | `Assoc fields -> Ok fields
  | `List items ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | `List [ `String key; value ] :: rest -> go ((key, value) :: acc) rest
        | item :: _ ->
            Error
              (Printf.sprintf "%s: expected a [key, value] pair, got %s" path
                 (Yojson.Safe.to_string item))
      in
      go [] items
  | _ -> Error (Printf.sprintf "%s: expected an object" path)

let map_of_pairs (pairs : (string * Yojson.Safe.t) list) : Yojson.Safe.t = `Assoc pairs

let map_of_numbers (pairs : (string * float) list) : Yojson.Safe.t =
  `Assoc (List.map (fun (key, value) -> (key, `Float value)) pairs)

let map_of_text (pairs : (string * string) list) : Yojson.Safe.t =
  `Assoc (List.map (fun (key, value) -> (key, `String value)) pairs)

let member name json =
  match json with `Assoc fields -> List.assoc_opt name fields | _ -> None

let text json = match json with `String text -> Ok text | _ -> Error "expected a string"

let number json =
  match json with
  | `Float number -> Ok number
  | `Int number -> Ok (float_of_int number)
  | `Intlit number -> (
      match float_of_string_opt number with
      | Some number -> Ok number
      | None -> Error "expected a number")
  | _ -> Error "expected a number"

let map : type value.
    string ->
    (Yojson.Safe.t -> (value, string) result) ->
    Yojson.Safe.t ->
    (value map, string) result =
 fun path of_value json ->
  match t_of_map path json with
  | Error message -> Error message
  | Ok pairs ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | (key, value) :: rest -> (
            match of_value value with
            | Ok value -> go ((key, value) :: acc) rest
            | Error message -> Error (Printf.sprintf "%s.%s: %s" path key message))
      in
      go [] pairs

let field : type value.
    string ->
    string ->
    (Yojson.Safe.t -> (value, string) result) ->
    Yojson.Safe.t ->
    (value, string) result =
 fun path name of_value json ->
  match member name json with
  | None -> Error (Printf.sprintf "%s: missing field %s" path name)
  | Some value -> (
      match of_value value with
      | Ok _ as ok -> ok
      | Error message -> Error (Printf.sprintf "%s.%s: %s" path name message))

let optional : type value.
    string ->
    string ->
    (Yojson.Safe.t -> (value, string) result) ->
    Yojson.Safe.t ->
    (value option, string) result =
 fun path name of_value json ->
  match member name json with
  | None | Some `Null -> Ok None
  | Some value -> (
      match of_value value with
      | Ok value -> Ok (Some value)
      | Error message -> Error (Printf.sprintf "%s.%s: %s" path name message))

(** {1 The answer records} *)

let t_of_choice_answer json =
  let ( let* ) = Result.bind in
  let path = "choice_answer" in
  let* choice = field path "choice" text json in
  let* probabilities =
    field path "probabilities" (map "choice_answer.probabilities" number) json
  in
  let* confidence = field path "confidence" number json in
  Ok { Types.choice; Types.probabilities; Types.confidence }

let t_of_score_answer json =
  let ( let* ) = Result.bind in
  let path = "score_answer" in
  let* score = field path "score" number json in
  let* legend = optional path "legend" (map "score_answer.legend" text) json in
  let* probabilities =
    field path "probabilities" (map "score_answer.probabilities" number) json
  in
  let* confidence = field path "confidence" number json in
  Ok { Types.score; Types.legend; Types.probabilities; Types.confidence }

(** {1 The unions} *)

let t_of_answer json =
  match member "type" json with
  | Some (`String "choice") ->
      Result.map (fun answer -> Choice answer) (t_of_choice_answer json)
  | Some (`String "score") ->
      Result.map (fun answer -> Score answer) (t_of_score_answer json)
  | Some (`String other) -> Error (Printf.sprintf "unknown answer type %S" other)
  | Some _ -> Error "the answer type must be a string"
  | None -> Error "the answer has no type field"

(* A question's criteria are a JSON object on the wire, so they are read and written
   here like an answer's probabilities. The values are the caller's JSON, `null` for an
   option without one, so the map is read without touching what it holds. *)
let t_of_choice_question json : (Types.choice_question, string) result =
  let ( let* ) = Result.bind in
  let path = "choice_question" in
  let* instructions = field path "instructions" (fun json -> Ok json) json in
  let* criteria =
    field path "criteria" (map "choice_question.criteria" (fun json -> Ok json)) json
  in
  Ok { Types.instructions; Types.criteria }

let t_of_score_question json : (Types.score_question, string) result =
  let ( let* ) = Result.bind in
  let path = "score_question" in
  let* instructions = field path "instructions" (fun json -> Ok json) json in
  let* levels =
    field path "criteria"
      (function
        | `List levels ->
            let rec go acc = function
              | [] -> Ok (List.rev acc)
              | `String level :: rest -> go (level :: acc) rest
              | item :: _ ->
                  Error
                    (Printf.sprintf "score_question.criteria: expected a string, got %s"
                       (Yojson.Safe.to_string item))
            in
            go [] levels
        | _ -> Error "expected an array of levels")
      json
  in
  Ok { Types.instructions; Types.levels }

let t_of_question json =
  match member "type" json with
  | Some (`String "choice") ->
      Result.map (fun question -> Choice_question question) (t_of_choice_question json)
  | Some (`String "score") ->
      Result.map (fun question -> Score_question question) (t_of_score_question json)
  | Some (`String other) -> Error (Printf.sprintf "unknown question type %S" other)
  | Some _ -> Error "the question type must be a string"
  | None -> Error "the question has no type field"

(** {1 Encoding} *)

let yojson_of_choice_answer (answer : Types.choice_answer) =
  `Assoc
    [
      ("choice", `String answer.Types.choice);
      ("probabilities", map_of_numbers answer.Types.probabilities);
      ("confidence", `Float answer.Types.confidence);
    ]

let yojson_of_score_answer (answer : Types.score_answer) =
  `Assoc
    ([
       ("score", `Float answer.Types.score);
       ("probabilities", map_of_numbers answer.Types.probabilities);
       ("confidence", `Float answer.Types.confidence);
     ]
    @
    match answer.Types.legend with
    | None -> []
    | Some legend -> [ ("legend", map_of_text legend) ])

let yojson_of_answer = function
  | Choice answer -> (
      match yojson_of_choice_answer answer with
      | `Assoc fields -> `Assoc (("type", `String "choice") :: fields)
      | json -> json)
  | Score answer -> (
      match yojson_of_score_answer answer with
      | `Assoc fields -> `Assoc (("type", `String "score") :: fields)
      | json -> json)

let yojson_of_choice_question (question : Types.choice_question) =
  `Assoc
    [
      ("type", `String "choice");
      ("instructions", question.Types.instructions);
      ("criteria", `Assoc question.Types.criteria);
    ]

let yojson_of_score_question (question : Types.score_question) =
  `Assoc
    [
      ("type", `String "score");
      ("instructions", question.Types.instructions);
      ("criteria", `List (List.map (fun level -> `String level) question.Types.levels));
    ]

let yojson_of_question = function
  | Choice_question question -> yojson_of_choice_question question
  | Score_question question -> yojson_of_score_question question

let yojson_of_response (response : response) =
  `Assoc
    (([
        ("model", `String response.model);
        ( "answers",
          `Assoc
            (List.map
               (fun (name, answer) -> (name, yojson_of_answer answer))
               response.answers) );
        ("usage", Types.yojson_of_usage response.usage);
      ]
     @ match response.id with None -> [] | Some id -> [ ("id", `String id) ])
    @
    match response.provider with
    | None -> []
    | Some provider -> [ ("provider", `String provider) ])

let yojson_of_request (request : request) =
  `Assoc
    [
      ("model", `String request.model);
      ("state", request.state);
      ( "questions",
        `Assoc
          (List.map
             (fun (name, question) -> (name, yojson_of_question question))
             request.questions) );
    ]

(** {1 The reply and the request} *)

(* A named member map, read in the order the reply lists it. Every failure names the
   field, so a caller reads [operation: ...] and not just a bad document. *)
let named : type value.
    (Yojson.Safe.t -> (value, string) result) ->
    Yojson.Safe.t ->
    ((string * value) list, string) result =
 fun decoder json ->
  match json with
  | `Assoc fields ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | (name, value) :: rest -> (
            match decoder value with
            | Ok decoded -> go ((name, decoded) :: acc) rest
            | Error message -> Error (Printf.sprintf "%s: %s" name message))
      in
      go [] fields
  | _ -> Error "expected an object"

let t_of_response json =
  let ( let* ) = Result.bind in
  let path = "response" in
  let* model = field path "model" text json in
  let* answers = field path "answers" (named t_of_answer) json in
  let* usage = field path "usage" Types.usage_of_yojson json in
  let* id = optional path "id" text json in
  let* provider = optional path "provider" text json in
  Ok { model; answers; usage; id; provider }

let response_of_yojson = t_of_response

let t_of_request json =
  let ( let* ) = Result.bind in
  let path = "request" in
  let* model = field path "model" text json in
  let* state = field path "state" (fun json -> Ok json) json in
  let* questions = field path "questions" (named t_of_question) json in
  Ok { model; state; questions }

(** {1 What a caller asks of an answer} *)

let choice ~instructions ~criteria =
  Choice_question { Types.instructions; Types.criteria }

let score ~instructions ~criteria =
  Score_question { Types.instructions; Types.levels = criteria }

let question_name = function Choice_question _ -> "choice" | Score_question _ -> "score"

let probability key (answer : Types.choice_answer) =
  List.assoc_opt key answer.probabilities

let level key (answer : Types.score_answer) =
  match answer.legend with None -> None | Some legend -> List.assoc_opt key legend

(* The check jev-ultrafast runs before it acts (`reference/model.py`, `validate_choice`):
   every number finite and in [0, 1], the distribution summing to 1 within 0.02, and the
   chosen key among the most probable. The client leaves it to the caller, because what a
   distribution must look like is the caller's decision; this is the reference rule so
   Leash can apply exactly it. *)
let choice_answer_valid (answer : Types.choice_answer) =
  let in_unit value = Float.is_finite value && value >= 0. && value <= 1. in
  let numbers = List.map snd answer.probabilities @ [ answer.confidence ] in
  List.for_all in_unit numbers
  && List.mem_assoc answer.choice answer.probabilities
  && Float.abs
       (List.fold_left (fun sum (_, value) -> sum +. value) 0. answer.probabilities -. 1.)
     < 0.02
  &&
  match probability answer.choice answer with
  | None -> false
  | Some chosen ->
      chosen
      >= List.fold_left
           (fun best (_, value) -> Float.max best value)
           neg_infinity answer.probabilities
         -. 1e-6
