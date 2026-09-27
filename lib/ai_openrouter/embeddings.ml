(* v1:openai_codec/embeddings.ml requests input as text or array of texts;
   indexed float arrays are preserved rather than reordering them. *)
type input = Text of string | Texts of string list
type request = { model : string; input : input; dimensions : int option }
type item = { index : int; vector : float list }
type response = { embeddings : item list; input_tokens : int option }

module Raw = struct
  type t = Eta_json.t

  let yojson_of_t json = json
  let t_of_yojson json = Ok json
end

type wire_request = { model : string; input : Raw.t; dimensions : int option }
[@@deriving yojson]

type wire_item = { index : int; embedding : float list }
[@@deriving yojson] [@@yojson.allow_extra_fields]

type wire_response = { data : wire_item list; usage : Raw.t option }
[@@deriving yojson] [@@yojson.allow_extra_fields]

let default_endpoint = "https://openrouter.ai/api/v1/embeddings"

let encode (request : request) =
  let input =
    match request.input with
    | Text text -> Eta_json.string text
    | Texts texts -> Eta_json.array (List.map Eta_json.string texts)
  in
  yojson_of_wire_request { model = request.model; input; dimensions = request.dimensions }

let decode json =
  match wire_response_of_yojson json with
  | Error message -> Common.invalid message json
  | Ok response ->
      if response.data = [] then Common.invalid ~path:"data" "empty embeddings" json
      else if
        List.exists
          (fun item ->
            item.embedding = []
            || List.exists (fun v -> not (Float.is_finite v)) item.embedding)
          response.data
      then Common.invalid ~path:"data.embedding" "empty or non-finite vector" json
      else
        Ok
          {
            embeddings =
              List.map
                (fun item -> { index = item.index; vector = item.embedding })
                response.data;
            input_tokens =
              Option.bind response.usage (fun u ->
                  match Eta_json.int_member "prompt_tokens" u with
                  | Some _ as tokens -> tokens
                  | None -> Eta_json.int_member "input_tokens" u);
          }

let create ~http ~clock ~logger ~api_key ?(endpoint = default_endpoint) ~deadline
    (request : request) =
  if
    request.model = ""
    || (match request.input with
      | Text text -> text = ""
      | Texts texts -> texts = [] || List.exists (( = ) "") texts)
    || match request.dimensions with Some n -> n <= 0 | None -> false
  then Common.invalid "model, input and dimensions must be valid" (encode request)
  else
    match
      Common.post ~http ~clock ~logger ~api_key ~endpoint ~deadline (encode request)
    with
    | Error _ as error -> error
    | Ok json -> decode json
