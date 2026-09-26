(* Tests for eta_observability.

   Story IDs covered here, one group per story:
   ^nobs-og4h  log writes one record with a timestamp, a level, the message,
               the fields and the fiber's inherited context
   ^nobs-2d4r  Context.with_fields attaches fields to everything logged in its
               dynamic extent, including in fibers forked inside
   ^nobs-ek28  the journal reporter writes one compact JSON object per line
               with a stable key order
   ^nobs-rayu  an in-memory reporter queries by level and field
   ^nobs-iedi  Redact.t prints <redacted> through every path
   ^nobs-262i  a per-logger minimum level and a rate limit for one message
   ^nobs-xovg  span logs start and end with elapsed time and an outcome
   ^nobs-6x58  the package depends on eta, eio and eta_json only (row 16 adds
               yojson for Redact.t's codecs, ^nnoschema-ifg0)

   The clocks are eta_test's mock clocks: the wall clock for timestamps, the
   monotonic clock for span elapsed time and rate-limit windows. *)

open Eta
open Eta_observability

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search index =
    if index + needle_length > haystack_length then false
    else if String.equal (String.sub haystack index needle_length) needle then true
    else search (index + 1)
  in
  needle_length = 0 || search 0

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let check_bool = Alcotest.(check bool)
let check_string = Alcotest.(check string)
let check_int = Alcotest.(check int)
let level_testable = Alcotest.testable Logger.pp_level ( = )

let field_text record name =
  match List.assoc_opt name record.Logger.fields with
  | Some value -> Format.asprintf "%a" Logger.pp_value value
  | None -> "<absent>"

(* The logger every test works with: our service name, a memory reporter, and
   the test's mock wall and monotonic clocks. *)
let make_logger ?(level = Logger.Info) ?(fields = []) env memory =
  Logger.create ~level ~fields ~service:"leash" ~clock:env#clock
    ~mono_clock:env#mono_clock
    ~reporter:(Logger.Memory.reporter memory)
    ()

let set_wall env seconds = Eio_mock.Clock.set_time env#clock seconds

let set_mono env seconds =
  Eio_mock.Clock.Mono.set_time env#mono_clock
    (Mtime.of_uint64_ns (Int64.of_float (seconds *. 1_000_000_000.)))

let record_count memory = List.length (Logger.Memory.records memory)

(* ^nobs-iedi: every rendering path of a wrapped secret prints <redacted>. *)
let test_redact_paths () =
  let secret = Redact.make "sk-live-1234" in
  check_string "pp" "<redacted>" (Format.asprintf "%a" Redact.pp secret);
  check_string "to_string" "<redacted>" (Redact.to_string secret);
  check_string "to_json" "\"<redacted>\"" (Eta_json.to_string (Redact.to_json secret));
  check_string "expose is the one revealing path" "sk-live-1234" (Redact.expose secret)

(* ^nobs-iedi: a secret reaches a record only as a Redacted field, and the line
   it produces contains the wrapper's rendering and never the secret. *)
let test_redact_in_record () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      Logger.info logger
        ~fields:[ ("api_key", Logger.Redacted (Redact.make "sk-live-1234")) ]
        "loaded";
      let line = Logger.to_string (List.hd (Logger.Memory.records memory)) in
      check_bool "the field renders redacted" true
        (contains line "\"api_key\":\"<redacted>\"");
      check_bool "the secret is absent" false (contains line "sk-live-1234"))

(* ^nnoschema-ifg0: the yojson codecs are the pair the deriver calls for a field of
   type Redact.t, so a secret is redacted by being of that type: encoded it is
   "<redacted>", decoded it is wrapped, and a non-string is refused with the
   offending subtree. *)
let test_redact_yojson () =
  let secret = Redact.make "sk-live-1234" in
  check_string "encoded redacted" "\"<redacted>\""
    (Yojson.Safe.to_string (Redact.yojson_of_t secret));
  (match Redact.t_of_yojson (`String "sk-live-1234") with
  | Ok decoded ->
      check_string "decoded wrapped and exposable" "sk-live-1234" (Redact.expose decoded)
  | Error message -> Alcotest.failf "string decodes: %s" message);
  match Redact.t_of_yojson (`Int 7) with
  | Ok _ -> Alcotest.fail "a non-string must not decode"
  | Error message ->
      check_bool "the refusal names the subtree" true (contains message "7")

(* ^nobs-2d4r: fields attached with with_fields reach records logged inside its
   extent and stop when it ends. *)
let test_context_extent () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      Context.with_fields
        [ ("tab", "t-1"); ("owner", "rafal") ]
        (fun () ->
          Alcotest.(check (list (pair string string)))
            "current inside"
            [ ("tab", "t-1"); ("owner", "rafal") ]
            (Context.fields (Context.current ()));
          Logger.info logger "inside");
      Logger.info logger "outside";
      let records = Logger.Memory.records memory in
      Alcotest.(check (list (pair string string)))
        "the record inherits them, sorted by name"
        [ ("owner", "rafal"); ("tab", "t-1") ]
        (List.nth records 0).Logger.context;
      Alcotest.(check (list (pair string string)))
        "the fiber's own fields after the extent" []
        (Context.fields (Context.current ()));
      Alcotest.(check (list (pair string string)))
        "the later record inherits nothing" [] (List.nth records 1).Logger.context)

(* ^nobs-2d4r: a fiber forked inside the extent inherits the fields. *)
let test_context_fork_inheritance () =
  Eta_test.run (fun env sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      Context.with_fields
        [ ("tab", "t-1") ]
        (fun () ->
          Eio.Fiber.fork ~sw (fun () -> Logger.info logger "forked");
          Eio.Fiber.yield ());
      let record = List.hd (Logger.Memory.records memory) in
      check_string "the forked fiber logged" "forked" record.msg;
      Alcotest.(check (list (pair string string)))
        "with the inherited field"
        [ ("tab", "t-1") ]
        record.Logger.context)

(* ^nobs-2d4r: nesting replaces a name in place, keeps the rest, and restores
   the outer set when the inner extent ends. *)
let test_context_nesting () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      Context.with_fields
        [ ("tab", "t-1"); ("owner", "outer") ]
        (fun () ->
          Context.with_fields
            [ ("owner", "inner"); ("cmd", "run") ]
            (fun () -> Logger.info logger "nested");
          Logger.info logger "restored");
      let records = Logger.Memory.records memory in
      Alcotest.(check (list (pair string string)))
        "the inner set wins where it speaks"
        [ ("cmd", "run"); ("owner", "inner"); ("tab", "t-1") ]
        (List.nth records 0).Logger.context;
      Alcotest.(check (list (pair string string)))
        "the outer set is restored"
        [ ("owner", "outer"); ("tab", "t-1") ]
        (List.nth records 1).Logger.context)

(* ^nobs-2d4r: outside an Eio fiber nothing is attached, and asking does not
   abort the caller. *)
let test_context_outside_fiber () =
  Alcotest.(check (list (pair string string)))
    "empty" []
    (Context.fields (Context.current ()));
  Alcotest.(check (list (pair string string)))
    "empty by construction" []
    (Context.fields Context.empty)

(* ^nobs-og4h: one record carries the timestamp, the level, the message, the
   event's fields and the fiber's inherited context. *)
let test_log_record () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      set_wall env 5.25;
      let logger = make_logger env memory in
      Context.with_fields
        [ ("tab", "t-1") ]
        (fun () ->
          Logger.log logger Logger.Warn ~msg:"degraded"
            ~fields:[ ("attempt", Logger.Int 2) ]
            ());
      let record = List.hd (Logger.Memory.records memory) in
      check_string "service" "leash" record.service;
      check_string "message" "degraded" record.msg;
      Alcotest.(check level_testable) "level" Logger.Warn record.level;
      Alcotest.(check (float 0.)) "timestamp from the wall clock" 5.25 record.ts;
      Alcotest.(check (list (pair string string)))
        "inherited context"
        [ ("tab", "t-1") ]
        record.Logger.context;
      check_string "the event's own field" "2" (field_text record "attempt");
      check_string "the line"
        "{\"ts\":\"1970-01-01T00:00:05.250Z\",\"level\":\"warn\",\"service\":\"leash\",\"msg\":\"degraded\",\"fields\":{\"attempt\":2},\"context\":{\"tab\":\"t-1\"}}"
        (Logger.to_string record))

(* ^nobs-og4h: base fields are defaults for every record; the record's own
   field with the same name wins. *)
let test_base_fields () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger =
        make_logger
          ~fields:[ ("version", Logger.String "1.2"); ("host", Logger.String "a") ]
          env memory
      in
      Logger.info logger ~fields:[ ("host", Logger.String "b") ] "hi";
      let record = List.hd (Logger.Memory.records memory) in
      Alcotest.(check (list (pair string string)))
        "merged and sorted"
        [ ("host", "b"); ("version", "1.2") ]
        (List.map
           (fun (name, value) -> (name, Format.asprintf "%a" Logger.pp_value value))
           record.fields))

(* ^nobs-ek28: the journal reporter writes one compact JSON object per line,
   with a fixed key order, and every line parses on its own. *)
let test_journal_lines () =
  Eta_test.run (fun env _sw ->
      let buffer = Buffer.create 256 in
      let logger =
        Logger.create ~service:"leash" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:(Logger.Reporter.journal (Eio.Flow.buffer_sink buffer))
          ()
      in
      Logger.info logger ~fields:[ ("port", Logger.Int 8080) ] "listening";
      Logger.warn logger
        ~fields:[ ("ratio", Logger.Float 0.5); ("retry", Logger.Bool true) ]
        "flapping";
      let lines =
        String.split_on_char '\n' (Buffer.contents buffer)
        |> List.filter (fun line -> not (String.equal line ""))
      in
      check_int "one line per record" 2 (List.length lines);
      check_string "first line, fixed key order"
        "{\"ts\":\"1970-01-01T00:00:00.000Z\",\"level\":\"info\",\"service\":\"leash\",\"msg\":\"listening\",\"fields\":{\"port\":8080}}"
        (List.nth lines 0);
      check_string "second line, fields sorted by name"
        "{\"ts\":\"1970-01-01T00:00:00.000Z\",\"level\":\"warn\",\"service\":\"leash\",\"msg\":\"flapping\",\"fields\":{\"ratio\":0.5,\"retry\":true}}"
        (List.nth lines 1);
      List.iter
        (fun line ->
          match Eta_json.parse line with
          | Ok _ -> ()
          | Error error ->
              Alcotest.failf "a journal line is not one JSON document: %a"
                Eta_json.pp_parse_error error)
        lines)

(* ^nobs-ek28: the timestamp is UTC with millisecond precision, and years
   before the epoch render too. *)
let test_journal_timestamp () =
  Eta_test.run (fun env _sw ->
      let buffer = Buffer.create 128 in
      let logger =
        Logger.create ~service:"leash" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:(Logger.Reporter.writer (fun line -> Buffer.add_string buffer line))
          ()
      in
      set_wall env 1_000_000_000.123;
      Logger.info logger "tick";
      check_bool "iso 8601 utc, millisecond precision" true
        (contains (Buffer.contents buffer) "\"ts\":\"2001-09-09T01:46:40.123Z\"");
      Buffer.clear buffer;
      set_wall env (-0.5);
      Logger.info logger "before the epoch";
      check_bool "negative epoch seconds floor correctly" true
        (contains (Buffer.contents buffer) "\"ts\":\"1969-12-31T23:59:59.500Z\""))

(* ^nobs-262i: a per-logger minimum level drops records below it. *)
let test_minimum_level () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger ~level:Logger.Warn env memory in
      check_bool "info is below the minimum" false (Logger.enabled logger Logger.Info);
      check_bool "warn is at the minimum" true (Logger.enabled logger Logger.Warn);
      check_bool "error is above the minimum" true (Logger.enabled logger Logger.Error);
      Logger.info logger "dropped";
      Logger.debug logger "dropped too";
      Logger.error logger "kept";
      check_int "only the record at or above the minimum" 1 (record_count memory);
      check_string "the kept one" "kept" (List.hd (Logger.Memory.records memory)).msg)

(* ^nobs-rayu: the in-memory reporter answers by level and by field. *)
let test_memory_find () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      Logger.info logger ~fields:[ ("tab", Logger.String "t-1") ] "first";
      Logger.error logger ~fields:[ ("tab", Logger.String "t-2") ] "second";
      Logger.error logger
        ~fields:[ ("token", Logger.Redacted (Redact.make "s3cret")) ]
        "third";
      check_int "by level" 2 (List.length (Logger.Memory.find ~level:Logger.Error memory));
      check_int "by field" 1
        (List.length (Logger.Memory.find ~field:("tab", "t-1") memory));
      check_int "by level and field" 1
        (List.length
           (Logger.Memory.find ~level:Logger.Error ~field:("tab", "t-2") memory));
      check_int "an absent field matches nothing" 0
        (List.length (Logger.Memory.find ~field:("tab", "nope") memory));
      check_int "a redacted field matches its rendering" 1
        (List.length (Logger.Memory.find ~field:("token", "<redacted>") memory));
      check_int "the secret itself matches nothing" 0
        (List.length (Logger.Memory.find ~field:("token", "s3cret") memory)))

(* ^nobs-262i: one message is written at most max times per window, measured on
   the monotonic clock, and each message name has its own budget. *)
let test_rate_limit () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let limit = Logger.limit ~max:2 ~window:(Duration.seconds 10) in
      for _ = 1 to 5 do
        Logger.warn logger ~limit "flapping"
      done;
      check_int "admitted twice in the first window" 2 (record_count memory);
      set_mono env 5.0;
      Logger.warn logger ~limit "flapping";
      check_int "the same window still holds" 2 (record_count memory);
      set_mono env 10.0;
      Logger.warn logger ~limit "flapping";
      check_int "the window resets after its duration" 3 (record_count memory);
      Logger.warn logger ~limit "another";
      check_int "a different message has its own budget" 4 (record_count memory);
      Logger.info logger "unlimited";
      check_int "a message without a limit is never dropped" 5 (record_count memory))

(* ^nobs-xovg: a successful span logs start and end with monotonic elapsed. *)
let test_span_ok () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let result =
        Logger.span logger "fetch" (fun () ->
            set_mono env 0.25;
            Ok 42)
      in
      Alcotest.(check (result int string))
        "the span returns what it wrapped" (Ok 42) result;
      let records = Logger.Memory.records memory in
      check_int "start and end" 2 (List.length records);
      let started = List.nth records 0 and finished = List.nth records 1 in
      check_string "start event" "start" (field_text started "event");
      check_string "end event" "end" (field_text finished "event");
      check_string "outcome" "ok" (field_text finished "outcome");
      check_string "elapsed on the monotonic clock" "250"
        (field_text finished "elapsed_ms");
      Alcotest.(check level_testable)
        "the end keeps the span's level" Logger.Info finished.level)

(* ^nobs-xovg: a typed failure is logged with its cause summary and returned. *)
let test_span_failure () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let result =
        Logger.span ~pp_err:Format.pp_print_string logger "fetch" (fun () -> Error "boom")
      in
      Alcotest.(check (result int string))
        "the failure travels unchanged" (Error "boom") result;
      let finished = List.nth (Logger.Memory.records memory) 1 in
      check_string "outcome" "failed" (field_text finished "outcome");
      check_string "cause summary" "Fail(boom)" (field_text finished "error");
      Alcotest.(check level_testable)
        "a failure is an error-level record" Logger.Error finished.level;
      ignore (Logger.span logger "fetch2" (fun () -> Error "boom"));
      let default_summary = List.nth (Logger.Memory.records memory) 3 in
      check_string "without a printer the summary names the cause" "Fail(<error>)"
        (field_text default_summary "error"))

(* ^nobs-xovg: a raise is logged as a defect and re-raised. *)
let test_span_defect () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let raised =
        match Logger.span logger "fetch" (fun () -> failwith "bad") with
        | _ -> Alcotest.fail "the exception was swallowed by the span"
        | exception Failure message -> message
      in
      check_string "the exception propagates" "bad" raised;
      let finished = List.nth (Logger.Memory.records memory) 1 in
      check_string "outcome" "defect" (field_text finished "outcome");
      check_string "the defect is summarized" "Die(Failure(\"bad\"))"
        (field_text finished "error");
      Alcotest.(check level_testable)
        "a defect is an error-level record" Logger.Error finished.level)

(* ^nobs-xovg: cancellation is an interruption, not a defect, and propagates. *)
let test_span_interrupt () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let cancelled =
        match
          Logger.span logger "fetch" (fun () ->
              raise (Eio.Cancel.Cancelled (Failure "stop")))
        with
        | _ -> false
        | exception Eio.Cancel.Cancelled _ -> true
      in
      check_bool "the interruption propagates" true cancelled;
      let finished = List.nth (Logger.Memory.records memory) 1 in
      check_string "outcome" "interrupt" (field_text finished "outcome");
      check_bool "an interruption carries no error summary" false
        (List.mem_assoc "error" finished.fields))

(* ^nobs-xovg: the span's records carry its own fields and the inherited
   context. *)
let test_span_fields_and_context () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      Context.with_fields
        [ ("tab", "t-1") ]
        (fun () ->
          ignore
            (Logger.span logger
               ~fields:[ ("url", Logger.String "https://example.test") ]
               "fetch"
               (fun () -> Ok ())));
      let records = Logger.Memory.records memory in
      check_int "start and end" 2 (List.length records);
      List.iter
        (fun record ->
          Alcotest.(check (list (pair string string)))
            "the inherited context"
            [ ("tab", "t-1") ]
            record.Logger.context;
          check_string "the span's own field" "https://example.test"
            (field_text record "url"))
        records)

(* ^nobs-262i ^nobs-xovg: the logger's minimum level applies to spans too. *)
let test_span_minimum_level () =
  Eta_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger ~level:Logger.Warn env memory in
      let result = Logger.span logger "quiet" (fun () -> Ok 1) in
      Alcotest.(check (result int string))
        "the span still returns its value" (Ok 1) result;
      check_int "a success below the minimum writes nothing" 0 (record_count memory);
      ignore
        (Logger.span ~pp_err:Format.pp_print_string logger "loud" (fun () -> Error "boom"));
      let records = Logger.Memory.records memory in
      check_int "only the failure record survives" 1 (List.length records);
      let record = List.hd records in
      check_string "and it is the end record" "end" (field_text record "event");
      check_string "with the failure outcome" "failed" (field_text record "outcome"))

(* ^nobs-6x58: the package depends on eta, eio and eta_json only — plus yojson,
   which row 16 admits for Redact.t's codecs (^nnoschema-ifg0, ADR-0007). The generated
   opam file is the contract, so this reads it: every runtime dependency must be
   one of those (plus Eio's own mtime type for the monotonic clock, and the
   compiler and build-tool entries dune generates). *)
let test_dependency_ceiling () =
  let lines = read_file "../../eta_observability.opam" |> String.split_on_char '\n' in
  let rec drop_while predicate = function
    | line :: rest when predicate line -> drop_while predicate rest
    | rest -> rest
  in
  let rec take_while predicate = function
    | line :: rest when predicate line -> line :: take_while predicate rest
    | _ -> []
  in
  let depends =
    lines |> drop_while (fun line -> not (String.starts_with ~prefix:"depends: [" line))
    |> function
    | [] -> Alcotest.fail "eta_observability.opam has no depends list"
    | _ :: rest -> take_while (fun line -> not (String.equal (String.trim line) "]")) rest
  in
  let name_of line =
    match String.index_opt line '"' with
    | None -> None
    | Some start -> (
        match String.index_from_opt line (start + 1) '"' with
        | None -> None
        | Some stop -> Some (String.sub line (start + 1) (stop - start - 1)))
  in
  let test_only line = contains line "with-test" || contains line "with-doc" in
  let runtime =
    List.filter_map
      (fun line ->
        match name_of line with
        | Some name when not (test_only line) -> Some name
        | _ -> None)
      depends
  in
  let allowed =
    [ "dune"; "ocaml"; "conf-eta-oxcaml"; "eta"; "eio"; "eta_json"; "yojson"; "mtime" ]
  in
  List.iter
    (fun name ->
      if not (List.mem name allowed) then
        Alcotest.failf "%s is outside eta_observability's dependency ceiling" name)
    runtime;
  List.iter
    (fun name ->
      if not (List.mem name runtime) then
        Alcotest.failf "%s is missing from eta_observability's runtime deps" name)
    [ "eta"; "eio"; "eta_json"; "yojson" ]

let () =
  Alcotest.run "eta_observability"
    (V1_logger.tests
    @ [
        ( "Redact",
          [
            Alcotest.test_case "prints <redacted> on every path (^nobs-iedi)" `Quick
              test_redact_paths;
            Alcotest.test_case "a record never carries the secret (^nobs-iedi)" `Quick
              test_redact_in_record;
            Alcotest.test_case "yojson codecs redact and wrap (^nnoschema-ifg0)" `Quick
              test_redact_yojson;
          ] );
        ( "Context",
          [
            Alcotest.test_case "fields reach records inside their extent (^nobs-2d4r)"
              `Quick test_context_extent;
            Alcotest.test_case "a forked fiber inherits the fields (^nobs-2d4r)" `Quick
              test_context_fork_inheritance;
            Alcotest.test_case "nesting replaces and restores (^nobs-2d4r)" `Quick
              test_context_nesting;
            Alcotest.test_case "outside an Eio fiber the context is empty (^nobs-2d4r)"
              `Quick test_context_outside_fiber;
          ] );
        ( "Logger",
          [
            Alcotest.test_case
              "one record with timestamp, level, message, fields and context (^nobs-og4h)"
              `Quick test_log_record;
            Alcotest.test_case "base fields are defaults (^nobs-og4h)" `Quick
              test_base_fields;
            Alcotest.test_case "a minimum level drops records below it (^nobs-262i)"
              `Quick test_minimum_level;
            Alcotest.test_case "a message is rate limited per window (^nobs-262i)" `Quick
              test_rate_limit;
          ] );
        ( "Journal",
          [
            Alcotest.test_case
              "one compact JSON object per line, fixed key order (^nobs-ek28)" `Quick
              test_journal_lines;
            Alcotest.test_case "timestamps are UTC milliseconds (^nobs-ek28)" `Quick
              test_journal_timestamp;
          ] );
        ( "Memory",
          [
            Alcotest.test_case "queries by level and by field (^nobs-rayu)" `Quick
              test_memory_find;
          ] );
        ( "Span",
          [
            Alcotest.test_case "start and end with elapsed time (^nobs-xovg)" `Quick
              test_span_ok;
            Alcotest.test_case "a typed failure is summarized (^nobs-xovg)" `Quick
              test_span_failure;
            Alcotest.test_case "a raise is a defect and propagates (^nobs-xovg)" `Quick
              test_span_defect;
            Alcotest.test_case "cancellation is an interruption (^nobs-xovg)" `Quick
              test_span_interrupt;
            Alcotest.test_case "spans carry fields and context (^nobs-xovg)" `Quick
              test_span_fields_and_context;
            Alcotest.test_case "a span respects the minimum level (^nobs-262i ^nobs-xovg)"
              `Quick test_span_minimum_level;
          ] );
        ( "Package",
          [
            Alcotest.test_case
              "depends on eta, eio, eta_json and yojson only (^nobs-6x58 ^nnoschema-ifg0)"
              `Quick test_dependency_ceiling;
          ] );
      ])
