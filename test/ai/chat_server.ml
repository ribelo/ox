(* The fake chat-completions server the chat tests drive (^nchat-kk3g).

   It is {!Fake_server} — the local plaintext listener on the caller's switch and clock,
   scripted one connection at a time — plus the shapes this endpoint's tests need: a reply
   every OpenAI-compatible server would send, and the one route the client posts to.

   Cancellation and finalizers: the accept loop is {!Fake_server}'s daemon of the caller's
   switch, so the switch's release cancels it. Nothing here registers a finalizer; the
   caller owns the switch, the clock and the net. *)

type t = Fake_server.t

let path = "/api/v1/chat/completions"
let url server = Fake_server.url server path
let connections = Fake_server.connections
let requests = Fake_server.requests
let request server = Fake_server.request server
let body server = Fake_server.body server
let ok = Fake_server.ok
let after = Fake_server.after

(* The reply OpenRouter sends for a JSON-object completion, including the members this
   client does not model (`object`, `created`, `logprobs`, `provider`, and the `cost`
   OpenRouter adds to `usage`). A fake that sent only the modelled members would let a
   decoder that refuses unknown members pass a test the real endpoint fails. *)
let reply ?(model = "inception/mercury-2.5") ?(content = {|{"text":"ada"}|})
    ?(finish_reason = Some "stop") ?(prompt_tokens = 11) ?(completion_tokens = 3)
    ?(total_tokens = 14) () =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("id", `String "gen-chat-1");
         ("object", `String "chat.completion");
         ("created", `Int 1759000000);
         ("model", `String model);
         ( "choices",
           `List
             [
               `Assoc
                 [
                   ("index", `Int 0);
                   ( "message",
                     `Assoc
                       [ ("role", `String "assistant"); ("content", `String content) ] );
                   ( "finish_reason",
                     match finish_reason with
                     | Some reason -> `String reason
                     | None -> `Null );
                   ("logprobs", `Null);
                 ];
             ] );
         ( "usage",
           `Assoc
             [
               ("prompt_tokens", `Int prompt_tokens);
               ("completion_tokens", `Int completion_tokens);
               ("total_tokens", `Int total_tokens);
               ("cost", `Float 0.00002);
             ] );
         ("provider", `String "Inception");
       ])

(* One scripted reply body per connection, answered in order; a connection past the script
   is closed with no reply at all, as {!Fake_server} does. *)
let serve ~net ~clock ~sw replies =
  Fake_server.serve ~net ~clock ~sw
    (List.concat_map (fun reply -> Fake_server.ok reply) replies)

(* The same server, for a test that needs a connection to fail or to be answered with a
   status: the script is {!Fake_server}'s own ({!ok}, {!after}, [Silent]). *)
let serve_scripts ~net ~clock ~sw scripts = Fake_server.serve ~net ~clock ~sw scripts
