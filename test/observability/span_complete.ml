(* Tests for Logger.span's result-derived completion fields.

   Story IDs covered here:
   ^nobs-pzpr  a completion-fields function over the returned result
   ^nobs-uwrx  HTTP status and sanitized provider outcome on the completed span
   ^nobs-tv72  row counts and nonsecret summaries on the same span
   ^nobs-yi3q  completion fields derived from a typed Error as well as Ok
   ^nobs-jc4q  the returned value or error is the very one the body returned
   ^nobs-3cck  static fields on start and end, completion fields only on end
   ^nobs-ze6n  base < static < completion < kernel-owned lifecycle fields
   ^nobs-h6pt  no extraction when the body raises or is cancelled; backtraces kept
   ^nobs-wrzs  a raising extractor is one defect end with its own backtrace
   ^nobs-a0se  one completion per span, redaction, sibling/nested isolation

   The Door/OTLP local-collector integration the spec's testing decisions name is
   left to the OTel slice; here the typed-record reporter is the OTLP-facing seam. *)

open Ox_observability

let check_bool = Alcotest.(check bool)
let check_string = Alcotest.(check string)
let check_int = Alcotest.(check int)
let level_testable = Alcotest.testable Logger.pp_level ( = )

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search index =
    if index + needle_length > haystack_length then false
    else if String.equal (String.sub haystack index needle_length) needle then true
    else search (index + 1)
  in
  needle_length = 0 || search 0

let field_text record name =
  match List.assoc_opt name record.Logger.fields with
  | Some value -> Format.asprintf "%a" Logger.pp_value value
  | None -> "<absent>"

let make_logger ?(fields = []) env memory =
  Logger.create ~fields ~service:"leash" ~clock:env#clock ~mono_clock:env#mono_clock
    ~reporter:(Logger.Memory.reporter memory)
    ()

let records memory = Logger.Memory.records memory

let ends memory name =
  List.filter
    (fun record ->
      String.equal record.Logger.msg name
      && String.equal (field_text record "event") "end")
    (records memory)

let only_end memory name =
  match ends memory name with
  | [ record ] -> record
  | found ->
      Alcotest.failf "expected one end record for %s, found %d" name (List.length found)

let start_of memory name =
  List.find
    (fun record ->
      String.equal record.Logger.msg name
      && String.equal (field_text record "event") "start")
    (records memory)

(* A counting extractor: how many times the span called it. *)
let counting extract =
  let calls = ref 0 in
  ( calls,
    fun result ->
      incr calls;
      extract result )

type response = { status : int; outcome : string; rows : int }

(* ^nobs-pzpr ^nobs-uwrx ^nobs-tv72 ^nobs-3cck: a successful body's status,
   sanitized outcome and row count land on the one end record, once. *)
let test_ok_completion () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let calls, complete =
        counting (function
          | Ok response ->
              [
                ("http.status", Logger.Int response.status);
                ("http.outcome", Logger.String response.outcome);
                ("rows", Logger.Int response.rows);
              ]
          | Error (_ : string) -> [])
      in
      let result =
        Logger.span logger ~complete
          ~fields:[ ("url", Logger.String "https://example.test") ]
          "ingest"
          (fun () -> Ok { status = 200; outcome = "accepted"; rows = 3 })
      in
      check_bool "the body's value" true (Result.is_ok result);
      check_int "^nobs-pzpr called exactly once" 1 !calls;
      check_int "^nobs-a0se one start and one end" 2 (List.length (records memory));
      let finished = only_end memory "ingest" in
      check_string "^nobs-uwrx status" "200" (field_text finished "http.status");
      check_string "^nobs-uwrx provider outcome" "accepted"
        (field_text finished "http.outcome");
      check_string "^nobs-tv72 row count" "3" (field_text finished "rows");
      check_string "kernel outcome untouched" "ok" (field_text finished "outcome");
      check_string "^nobs-3cck static field on end" "https://example.test"
        (field_text finished "url");
      let started = start_of memory "ingest" in
      check_string "^nobs-3cck static field on start" "https://example.test"
        (field_text started "url");
      List.iter
        (fun name ->
          check_string
            ("^nobs-3cck no " ^ name ^ " on start")
            "<absent>" (field_text started name))
        [ "http.status"; "http.outcome"; "rows" ])

(* ^nobs-yi3q: a typed Error yields its known status on the failed end record,
   next to the kernel's cause summary. *)
let test_error_completion () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let calls, complete =
        counting (function
          | Ok (_ : int) -> []
          | Error (`Http status) -> [ ("http.status", Logger.Int status) ])
      in
      let pp_err fmt (`Http status) = Format.fprintf fmt "http %d" status in
      let result =
        Logger.span logger ~pp_err ~complete "fetch" (fun () -> Error (`Http 503))
      in
      check_bool "the typed error returns" true (result = Error (`Http 503));
      check_int "called once on Error" 1 !calls;
      let finished = only_end memory "fetch" in
      check_string "^nobs-yi3q status from Error" "503"
        (field_text finished "http.status");
      check_string "outcome failed" "failed" (field_text finished "outcome");
      check_string "kernel error summary" "Fail(http 503)" (field_text finished "error");
      Alcotest.(check level_testable) "error level" Logger.Error finished.level)

(* ^nobs-jc4q: the span returns the physically identical Ok and Error values. *)
let test_identity () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let complete _ = [ ("seen", Logger.Bool true) ] in
      let ok : (int ref, string ref) result = Ok (ref 1) in
      let error : (int ref, string ref) result = Error (ref "boom") in
      check_bool "^nobs-jc4q Ok is the same value" true
        (Logger.span logger ~complete "ok" (fun () -> ok) == ok);
      check_bool "^nobs-jc4q Error is the same value" true
        (Logger.span logger ~complete "error" (fun () -> error) == error))

(* ^nobs-3cck: while the body runs, nothing is extracted and no completion field
   is visible in records or context. *)
let test_not_before_completion () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let calls, complete =
        counting (fun (_ : (int, string) result) -> [ ("rows", Logger.Int 7) ])
      in
      let calls_inside = ref (-1) in
      ignore
        (Logger.span logger ~complete "ingest" (fun () ->
             calls_inside := !calls;
             Logger.info logger "inside";
             Ok 7));
      check_int "^nobs-3cck not called while the body runs" 0 !calls_inside;
      let inside =
        List.find (fun r -> String.equal r.Logger.msg "inside") (records memory)
      in
      check_string "no completion field inside" "<absent>" (field_text inside "rows");
      check_bool "no completion field in the inside context" false
        (List.mem_assoc "rows" inside.context);
      check_string "on the end record" "7" (field_text (only_end memory "ingest") "rows"))

(* ^nobs-ze6n: base < static < completion < kernel-owned, on the end record;
   the kernel's event wins on the start record too. *)
let test_precedence () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger =
        make_logger
          ~fields:
            [
              ("k", Logger.String "base");
              ("b", Logger.String "base");
              ("s", Logger.String "base");
              ("error", Logger.String "base-error");
            ]
          env memory
      in
      let complete (_ : (int, string) result) =
        [
          ("k", Logger.String "completion");
          ("event", Logger.String "forged");
          ("outcome", Logger.String "forged");
          ("elapsed_ms", Logger.Int 999_999);
          ("error", Logger.String "forged");
        ]
      in
      ignore
        (Logger.span logger ~complete
           ~fields:
             [
               ("k", Logger.String "static");
               ("s", Logger.String "static");
               ("event", Logger.String "forged");
             ]
           "op"
           (fun () -> Ok 1));
      let started = start_of memory "op" and finished = only_end memory "op" in
      check_string "base alone" "base" (field_text finished "b");
      check_string "static over base" "static" (field_text finished "s");
      check_string "completion over static" "completion" (field_text finished "k");
      check_string "kernel event" "end" (field_text finished "event");
      check_string "kernel outcome" "ok" (field_text finished "outcome");
      check_string "kernel elapsed" "0" (field_text finished "elapsed_ms");
      check_string "no forged error on an ok end" "<absent>" (field_text finished "error");
      check_string "kernel event on start" "start" (field_text started "event");
      check_string "start: static over base" "static" (field_text started "k");
      let names = List.map fst finished.fields in
      check_int "no duplicate names" (List.length names)
        (List.length (List.sort_uniq String.compare names));
      ignore
        (Logger.span logger ~complete ~pp_err:Format.pp_print_string "failing" (fun () ->
             Error "boom"));
      let failed = only_end memory "failing" in
      check_string "kernel error over completion" "Fail(boom)" (field_text failed "error");
      check_string "kernel outcome over completion" "failed" (field_text failed "outcome"))

let backtrace_has_line backtrace line =
  contains (Printexc.raw_backtrace_to_string backtrace) (Printf.sprintf "line %d" line)

(* ^nobs-h6pt: a raising body is never given to the extractor; its defect and
   backtrace propagate unchanged. *)
let test_body_defect_skips () =
  Printexc.record_backtrace true;
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let calls, complete =
        counting (fun (_ : (int, string) result) -> [ ("rows", Logger.Int 1) ])
      in
      let body_line = __LINE__ + 1 in
      let body () = raise (Failure "body") in
      match Logger.span logger ~complete "op" body with
      | _ -> Alcotest.fail "the body's exception was swallowed"
      | exception (Failure message as _exn) ->
          let backtrace = Printexc.get_raw_backtrace () in
          check_string "the body's exception" "body" message;
          check_bool "^nobs-h6pt the body's backtrace" true
            (backtrace_has_line backtrace body_line);
          check_int "^nobs-h6pt extractor not called" 0 !calls;
          let finished = only_end memory "op" in
          check_string "defect" "defect" (field_text finished "outcome");
          check_string "no completion field" "<absent>" (field_text finished "rows"))

(* ^nobs-h6pt: external Eio cancellation of the body is an interruption; the
   extractor is never called and the cancellation propagates. *)
let test_cancellation_skips () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let calls, complete =
        counting (fun (_ : (int, string) result) -> [ ("rows", Logger.Int 1) ])
      in
      let propagated = ref false in
      let winner =
        Eio.Fiber.first
          (fun () ->
            match
              Logger.span logger ~complete "op" (fun () -> Eio.Fiber.await_cancel ())
            with
            | result -> result
            | exception (Eio.Cancel.Cancelled _ as cancelled) ->
                propagated := true;
                raise cancelled)
          (fun () -> Ok 0)
      in
      check_bool "the other branch won" true (winner = Ok 0);
      check_bool "^nobs-h6pt the cancellation propagated" true !propagated;
      check_int "^nobs-h6pt extractor not called" 0 !calls;
      let finished = only_end memory "op" in
      check_string "interrupt" "interrupt" (field_text finished "outcome");
      check_string "no completion field" "<absent>" (field_text finished "rows"))

(* ^nobs-wrzs: a raising extractor yields one defect end — never an ok/failed
   end as well — and its own exception and backtrace propagate. *)
let test_extractor_defect () =
  Printexc.record_backtrace true;
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let boom = Failure "extractor" in
      let extractor_line = __LINE__ + 1 in
      let complete (_ : (int, string) result) = raise boom in
      let check_case name body =
        match
          Logger.span logger ~complete ~fields:[ ("url", Logger.String "u") ] name body
        with
        | _ -> Alcotest.fail "the extractor's exception was swallowed"
        | exception exn ->
            let backtrace = Printexc.get_raw_backtrace () in
            check_bool "^nobs-wrzs the extractor's own exception" true (exn == boom);
            check_bool "^nobs-wrzs the extractor's backtrace" true
              (backtrace_has_line backtrace extractor_line);
            let named =
              List.filter (fun r -> String.equal r.Logger.msg name) (records memory)
            in
            check_int "^nobs-wrzs one start and one end" 2 (List.length named);
            let finished = only_end memory name in
            check_string "^nobs-wrzs defect outcome" "defect"
              (field_text finished "outcome");
            check_string "the extractor's defect summarized" "Die(Failure(\"extractor\"))"
              (field_text finished "error");
            check_string "static field kept" "u" (field_text finished "url");
            Alcotest.(check level_testable) "error level" Logger.Error finished.level
      in
      check_case "after-ok" (fun () -> Ok 1);
      check_case "after-error" (fun () -> Error "provider"))

(* ^nobs-a0se: a Redacted completion value stays redacted in the memory store,
   the journal line and the typed records an exporter consumes. *)
let test_redacted_completion () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let buffer = Buffer.create 256 in
      let typed = ref [] in
      let logger =
        Logger.create ~service:"leash" ~clock:env#clock ~mono_clock:env#mono_clock
          ~reporter:
            (Logger.Reporter.tee
               [
                 Logger.Memory.reporter memory;
                 Logger.Reporter.journal (Eio.Flow.buffer_sink buffer);
                 Logger.Reporter.records (fun record -> typed := record :: !typed);
               ])
          ()
      in
      ignore
        (Logger.span logger
           ~complete:(fun (_ : (string, string) result) ->
             [ ("session", Logger.Redacted (Redact.make "sk-live-1234")) ])
           "login"
           (fun () -> Ok "sk-live-1234"));
      check_int "memory: redacted" 1
        (List.length (Logger.Memory.find ~field:("session", "<redacted>") memory));
      check_int "memory: the secret matches nothing" 0
        (List.length (Logger.Memory.find ~field:("session", "sk-live-1234") memory));
      let journal = Buffer.contents buffer in
      check_bool "journal: redacted" true (contains journal "\"session\":\"<redacted>\"");
      check_bool "journal: secret absent" false (contains journal "sk-live-1234");
      let finished = List.hd !typed in
      (match List.assoc_opt "session" finished.Logger.fields with
      | Some (Logger.Redacted _ as value) ->
          check_string "records: JSON redacted" "\"<redacted>\""
            (Ox_json.to_string (Logger.value_to_json value))
      | _ -> Alcotest.fail "the typed record lost the Redacted value");
      check_bool "records: secret absent" false
        (contains (Logger.to_string finished) "sk-live-1234"))

(* ^nobs-a0se: sibling spans keep their own completion; nested spans do not
   leak fields to each other or into context; one completion per span. *)
let test_isolation () =
  Ox_test.run (fun env _sw ->
      let memory = Logger.Memory.create () in
      let logger = make_logger env memory in
      let rows n (_ : (int, string) result) = [ ("rows", Logger.Int n) ] in
      let sibling name n =
        ignore
          (Logger.span logger ~complete:(rows n) name (fun () ->
               Eio.Fiber.yield ();
               Logger.info logger (name ^ "-inside");
               Eio.Fiber.yield ();
               Ok n))
      in
      Eio.Fiber.both (fun () -> sibling "a" 1) (fun () -> sibling "b" 2);
      check_string "sibling a" "1" (field_text (only_end memory "a") "rows");
      check_string "sibling b" "2" (field_text (only_end memory "b") "rows");
      let outer_calls, outer_complete =
        counting (fun (_ : (int, string) result) -> [ ("outer.rows", Logger.Int 10) ])
      in
      let inner_calls, inner_complete =
        counting (fun (_ : (int, string) result) -> [ ("inner.rows", Logger.Int 20) ])
      in
      ignore
        (Logger.span logger ~complete:outer_complete "outer" (fun () ->
             ignore
               (Logger.span logger ~complete:inner_complete "inner" (fun () -> Ok 20));
             Logger.info logger "after-inner";
             Ok 10));
      check_int "outer once" 1 !outer_calls;
      check_int "inner once" 1 !inner_calls;
      let outer = only_end memory "outer" and inner = only_end memory "inner" in
      check_string "outer's own" "10" (field_text outer "outer.rows");
      check_string "inner's own" "20" (field_text inner "inner.rows");
      check_string "inner's not on outer" "<absent>" (field_text outer "inner.rows");
      check_string "outer's not on inner" "<absent>" (field_text inner "outer.rows");
      let after =
        List.find (fun r -> String.equal r.Logger.msg "after-inner") (records memory)
      in
      check_string "nothing on a later log" "<absent>" (field_text after "inner.rows");
      List.iter
        (fun record ->
          List.iter
            (fun name ->
              check_bool "no result field in context" false
                (List.mem_assoc name record.Logger.context))
            [ "rows"; "outer.rows"; "inner.rows" ])
        (records memory);
      Alcotest.(check (list (pair string string)))
        "no result field remains in context after the span" []
        (Context.fields (Context.current ())))

let tests =
  [
    ( "Span completion",
      [
        Alcotest.test_case
          "Ok yields status, outcome and rows on the end (^nobs-pzpr ^nobs-uwrx \
           ^nobs-tv72 ^nobs-3cck)"
          `Quick test_ok_completion;
        Alcotest.test_case "a typed Error yields fields too (^nobs-yi3q)" `Quick
          test_error_completion;
        Alcotest.test_case "the returned value is physically unchanged (^nobs-jc4q)"
          `Quick test_identity;
        Alcotest.test_case "nothing is extracted before completion (^nobs-3cck)" `Quick
          test_not_before_completion;
        Alcotest.test_case "base < static < completion < kernel (^nobs-ze6n)" `Quick
          test_precedence;
        Alcotest.test_case "a raising body is not extracted (^nobs-h6pt)" `Quick
          test_body_defect_skips;
        Alcotest.test_case "a cancelled body is not extracted (^nobs-h6pt)" `Quick
          test_cancellation_skips;
        Alcotest.test_case "a raising extractor is one defect end (^nobs-wrzs)" `Quick
          test_extractor_defect;
        Alcotest.test_case "completion values stay redacted (^nobs-a0se)" `Quick
          test_redacted_completion;
        Alcotest.test_case "siblings and nested spans stay isolated (^nobs-a0se)" `Quick
          test_isolation;
      ] );
  ]
