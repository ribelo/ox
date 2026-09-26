(* Historical logger cases ^nport-lve1, adapted to the journal contract.
   v1's pretty/logfmt and stdout/stderr routes no longer exist. *)
open Eta_observability

let check_string = Alcotest.(check string)
let check_int = Alcotest.(check int)

let make ?(level = Logger.Info) reporter env =
  Logger.create ~level ~service:"ported" ~clock:env#clock ~mono_clock:env#mono_clock
    ~reporter ()

let level_and_fields () =
  Eio_mock.Backend.run_full (fun env ->
      let memory = Logger.Memory.create () in
      let logger = make ~level:Logger.Warn (Logger.Memory.reporter memory) env in
      Logger.info logger "filtered";
      Logger.warn logger ~fields:[ ("user", Logger.String "alice") ] "warning";
      Logger.error logger ~fields:[ ("count", Logger.Int 7) ] "failed";
      let records = Logger.Memory.records memory in
      check_int "with_min_level" 2 (List.length records);
      check_string "first retained" "warning" (List.hd records).msg;
      check_string "second retained" "failed" (List.nth records 1).msg;
      check_string "user field" "alice"
        (Format.asprintf "%a" Logger.pp_value
           (List.assoc "user" (List.hd records).fields));
      check_string "count field" "7"
        (Format.asprintf "%a" Logger.pp_value
           (List.assoc "count" (List.nth records 1).fields));
      List.iter
        (fun (level, name) ->
          check_string "formatters" name (Logger.level_to_string level);
          check_string "level pretty printer" name
            (Format.asprintf "%a" Logger.pp_level level))
        [
          (Logger.Debug, "debug");
          (Logger.Info, "info");
          (Logger.Warn, "warn");
          (Logger.Error, "error");
        ])

let json_escapes () =
  let record =
    {
      Logger.ts = 1.234;
      level = Info;
      service = "test";
      msg = "quote \" newline\n";
      fields = [ ("k", Logger.String "tab\t") ];
      context = [];
    }
  in
  check_string "json escapes values"
    "{\"ts\":\"1970-01-01T00:00:01.234Z\",\"level\":\"info\",\"service\":\"test\",\"msg\":\"quote \
     \\\" newline\\n\",\"fields\":{\"k\":\"tab\\t\"}}"
    (Logger.to_string record)

let writer_recovers () =
  Eio_mock.Backend.run_full (fun env ->
      let calls = ref 0 in
      let logger =
        make
          (Logger.Reporter.writer (fun _ ->
               incr calls;
               if !calls = 1 then failwith "writer once"))
          env
      in
      (match Logger.info logger "first" with
      | exception Failure message -> check_string "writer defect" "writer once" message
      | _ -> Alcotest.fail "writer defect must propagate");
      Logger.info logger "recovered";
      check_int "writer retried on next record" 2 !calls)

let tests =
  [
    ( "v1 Logger ^nport-lve1",
      [
        Alcotest.test_case "minimum level, structured fields, severity names" `Quick
          level_and_fields;
        Alcotest.test_case "JSON escaping" `Quick json_escapes;
        Alcotest.test_case "writer exception then success" `Quick writer_recovers;
      ] );
  ]
