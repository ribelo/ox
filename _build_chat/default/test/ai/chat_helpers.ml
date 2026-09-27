(* Shared setup for the chat tests (^nchat-kk3g): the client points at {!Chat_server} and
   the logger keeps its records in memory, so nothing here reaches the network.

   The clock is Eio's real one, exactly as in `test_helpers.ml`: advancing a mock clock
   needs the test fiber to run while the client's socket wait needs the scheduler to poll,
   and one domain cannot do both. The backoff (100 ms) and an attempt's cap (50 ms) are
   therefore real and short. *)

let chat_model = "inception/mercury-2.5"
let chat_key = Eta_observability.Redact.make "test-chat-key"

(* Long enough that both attempts and the backoff fit inside it. *)
let chat_deadline = Eta.Duration.seconds 5

(* One attempt's read cap, when a test wants an attempt to time out quickly. *)
let attempt_timeout = Eta.Duration.ms 50

let system =
  Eta_ai_chat.Types.{ role = System; content = "Answer with one JSON object." }

let user content = Eta_ai_chat.Types.{ role = User; content }
let chat_messages = [ system; user {|{"goal":"type ada"}|} ]

(* The helpers `test_helpers.ml` keeps for both AI clients. *)
let run = Test_helpers.run
let memory_logger = Test_helpers.memory_logger
let expect_ok = Test_helpers.expect_ok
let expect_error = Test_helpers.expect_error
let jbody = Test_helpers.jbody
let member = Test_helpers.member
let text_of = Test_helpers.text_of
let list_of = Test_helpers.list_of
let contains = Test_helpers.contains
let expect_part = Test_helpers.expect_part

let member_opt name json =
  match json with `Assoc fields -> List.assoc_opt name fields | _ -> None

let has_member name json = Option.is_some (member_opt name json)

let client ~sw env server ?endpoint ?logger ?timeout () =
  let http = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
  let logger =
    match logger with Some logger -> logger | None -> fst (memory_logger env)
  in
  let endpoint =
    match endpoint with Some endpoint -> endpoint | None -> Chat_server.url server
  in
  Eta_ai_chat.Chat.create ~http ~clock:env#clock ~logger ~endpoint ~api_key:chat_key
    ?timeout ()

(* One call with the story's defaults filled in, so a test says only what it tests. *)
let complete client ?(model = chat_model) ?(deadline = chat_deadline)
    ?(messages = chat_messages) ?max_tokens ?json_object ?reasoning () =
  Eta_ai_chat.Chat.complete client ~deadline ~model ~messages ?max_tokens ?json_object
    ?reasoning ()
