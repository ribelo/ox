(* The value a caller gets and the step that extracts it from a reply.

   A completion is the first choice's message plus what the reply said about itself: the
   model that answered, why generation stopped, the usage and the request id. The usage
   travels whole, so the provider's own cost — when the reply reports one — reaches the
   caller as [completion.usage.cost] (^nchat-qu3j). A reply that names no choice is refused
   here, so {!Chat.complete} never invents a content. *)

type completion = {
  content : string;
  model : string;
  finish_reason : string option;
  usage : Types.usage;
  id : string option;
}

let completion_of_response (response : Types.response) =
  match response.Types.choices with
  | [] -> Error "the reply names no choice"
  | choice :: _ ->
      Ok
        {
          content = choice.Types.message.Types.content;
          model = response.Types.model;
          finish_reason = choice.Types.finish_reason;
          usage = response.Types.usage;
          id = response.Types.id;
        }
