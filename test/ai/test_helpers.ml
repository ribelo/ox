(* Shared setup for the System One tests: the client points at {!Fake_server} and the
   logger keeps its records in memory, so nothing here reaches the network (^nso-hcfr).

   The clock is Eio's real one. The mock clock cannot drive these tests: advancing it
   requires the test fiber to run, while the client's socket wait requires the scheduler to
   poll, and one domain cannot do both — the retry backoff and the attempt deadlines are
   therefore short and real (100 ms, 50 ms, 30 ms), which costs about a second in total. *)

let model = "typesafe/jev-1.13-20260917"
let key = Ox_observability.Redact.make "test-key"

(* Long enough that both attempts and the backoff fit inside it. *)
let deadline = Ox.Duration.seconds 5

(* One attempt's read cap, when a test wants an attempt to time out quickly. *)
let attempt_timeout = Ox.Duration.ms 50

(* A peer that never answers, for a timeout to fire against. *)
let stall = Ox.Duration.seconds 1
let state = `Assoc [ ("page", `Assoc [ ("url", `String "https://example.test/") ]) ]

let choice_questions =
  [
    ( "operation",
      Ox_ai_systemone.Codecs.choice
        ~instructions:(Ox_json.object_ [ ("goal", Some (Ox_json.string "buy a ticket")) ])
        ~criteria:[ ("CLICK", Ox_json.string "Click"); ("DONE", `Null) ] );
  ]

let response_body =
  {|{"model":"typesafe/jev-1.13-20260917","answers":{"operation":{"type":"choice","choice":"CLICK","probabilities":{"CLICK":0.9,"DONE":0.1},"confidence":0.8}},"usage":{"input_tokens":10,"output_tokens":2,"cost":0.0001},"id":"gen-1","provider":"TypeSafe"}|}

(* The real environment: a real clock and the real network, in one switch. *)
let run f = Eio_main.run (fun env -> Eio.Switch.run (fun sw -> f ~sw env))

let memory_logger env =
  let memory = Ox_observability.Logger.Memory.create () in
  let logger =
    Ox_observability.Logger.create ~level:Ox_observability.Logger.Debug
      ~service:"ox_ai_test" ~clock:env#clock ~mono_clock:env#mono_clock
      ~reporter:(Ox_observability.Logger.Memory.reporter memory)
      ()
  in
  (logger, memory)

let client ~sw env server ?endpoint ?logger ?timeout () =
  let http = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
  let logger =
    match logger with Some logger -> logger | None -> fst (memory_logger env)
  in
  let endpoint =
    match endpoint with
    | Some endpoint -> endpoint
    | None -> Fake_server.url server "/v1/systemone"
  in
  Ox_ai_systemone.Client.create ~http ~clock:env#clock ~logger ~endpoint ~api_key:key
    ~model ?timeout ()

let expect_ok = function
  | Ok value -> value
  | Error error -> Alcotest.failf "expected Ok, got %s" (Ox_ai.Error.to_string error)

let expect_error = function
  | Error error -> error
  | Ok _ -> Alcotest.fail "expected Error"

(* Reading the recorded request. *)
let jbody server = Yojson.Safe.from_string (Fake_server.body server)

let member name json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some value -> value
      | None -> Alcotest.failf "no member %s" name)
  | _ -> Alcotest.failf "member %s of a non-object" name

let text_of = function
  | `String text -> text
  | json -> Alcotest.failf "not a string: %s" (Yojson.Safe.to_string json)

let list_of = function
  | `List items -> items
  | json -> Alcotest.failf "not a list: %s" (Yojson.Safe.to_string json)

let contains hay needle =
  let rec go index =
    index + String.length needle <= String.length hay
    && (String.equal (String.sub hay index (String.length needle)) needle
       || go (index + 1))
  in
  go 0

let expect_part where needle = Alcotest.(check bool) needle true (contains where needle)
