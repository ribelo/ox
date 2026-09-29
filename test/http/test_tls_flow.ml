(* nhttp-7pp8 nhttp-rs5p: Pie's lifecycle_soak WSS fixture pulled row 38. *)
module H = Ox_http
module S = H.Ox_http_tls_openssl

let local = Eio.Net.Ipaddr.V4.loopback

let with_pair server client =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 5. (fun () ->
          Eio.Switch.run (fun sw ->
              let listener = Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (local, 0)) in
              let address = Eio.Net.listening_addr listener in
              Eio.Fiber.both
                (fun () ->
                  let raw, _ = Eio.Net.accept ~sw listener in
                  let ctx =
                    S.create_server_ctx ~certificate_chain_file:"localhost.crt"
                      ~private_key_file:"localhost.key" ~alpn_protocols:[ "http/1.1" ] ()
                  in
                  let ssl = S.create_server_ssl ctx in
                  let flow =
                    H.Tls_flow.create ~raw:(raw :> H.Tls_flow.ty Eio.Resource.t) ~ssl
                  in
                  server raw ssl flow)
                (fun () ->
                  let raw = Eio.Net.connect ~sw env#net address in
                  let ctx = S.create_ctx () in
                  S.ctx_load_ca ctx "localhost.crt";
                  let ssl =
                    S.create_ssl ctx ~hostname:(Some "localhost") ~ip:None
                      ~alpn_protocols:[ "http/1.1" ]
                  in
                  let flow =
                    H.Tls_flow.create ~raw:(raw :> H.Tls_flow.ty Eio.Resource.t) ~ssl
                  in
                  client raw ssl flow))))

let expect_eof flow =
  Alcotest.check_raises "end of stream" End_of_file (fun () ->
      ignore (Eio.Flow.single_read flow (Cstruct.create 32)))

let expect_failure flow =
  match Eio.Flow.single_read flow (Cstruct.create 32) with
  | _ -> Alcotest.fail "damaged TLS record accepted"
  | exception H.Tls_flow.Tls_failure detail ->
      Alcotest.(check bool) "failure carries a diagnostic" true (detail <> "")

let read_message flow expected =
  let actual = Cstruct.create (String.length expected) in
  Eio.Flow.read_exact flow actual;
  Alcotest.(check string)
    "complete message before EOF" expected (Cstruct.to_string actual)

let unnotified_eof () =
  (* nhttp-7pp8: includes multiple records and buffered plaintext, with tiny reads. *)
  let message = String.make 40000 'x' in
  with_pair
    (fun raw _ flow ->
      Eio.Flow.copy_string message flow;
      Eio.Flow.close raw)
    (fun _ _ flow ->
      let output = Buffer.create (String.length message) in
      let dst = Cstruct.create 7 in
      let rec read () =
        match Eio.Flow.single_read flow dst with
        | n ->
            Buffer.add_string output (Cstruct.to_string (Cstruct.sub dst 0 n));
            read ()
        | exception End_of_file -> ()
      in
      read ();
      Alcotest.(check string) "all records drained" message (Buffer.contents output);
      expect_eof flow)

let server_close () =
  (* nhttp-rs5p nhttp-7pp8: close emits close_notify before closing the socket. *)
  with_pair
    (fun _ _ flow ->
      Eio.Flow.copy_string "last message" flow;
      Eio.Flow.close flow;
      Eio.Flow.close flow)
    (fun raw ssl flow ->
      read_message flow "last message";
      expect_eof flow;
      let dst = Cstruct.create 1 in
      (match S.read ssl (Cstruct.to_bigarray dst) 0 1 with
      | S.Io_error { code = 6; _ } -> ()
      | _ -> Alcotest.fail "peer did not receive close_notify");
      expect_eof raw;
      Eio.Flow.close flow;
      Eio.Flow.close flow)

let client_close () =
  (* nhttp-rs5p: the same close capability works for a client. *)
  with_pair
    (fun raw ssl flow ->
      read_message flow "finished";
      expect_eof flow;
      let dst = Cstruct.create 1 in
      (match S.read ssl (Cstruct.to_bigarray dst) 0 1 with
      | S.Io_error { code = 6; _ } -> ()
      | _ -> Alcotest.fail "server did not receive close_notify");
      expect_eof raw)
    (fun _ _ flow ->
      Eio.Flow.copy_string "finished" flow;
      Eio.Flow.close flow;
      Eio.Flow.close flow)

let record ssl =
  let plain = Cstruct.of_string "next message" in
  (match S.write ssl (Cstruct.to_bigarray plain) 0 (Cstruct.length plain) with
  | S.Io_bytes n -> Alcotest.(check int) "encrypted message" (Cstruct.length plain) n
  | S.Io_error _ -> Alcotest.fail "could not prepare TLS record");
  let wire = Cstruct.create (S.bio_write_pending ssl) in
  let n = S.bio_read ssl (Cstruct.to_bigarray wire) 0 (Cstruct.length wire) in
  Alcotest.(check int) "complete wire record" (Cstruct.length wire) n;
  wire

let damaged_record transform =
  with_pair
    (fun raw ssl flow ->
      Eio.Flow.copy_string "good" flow;
      Eio.Flow.write raw [ transform (record ssl) ];
      Eio.Flow.close raw)
    (fun _ _ flow ->
      read_message flow "good";
      expect_failure flow)

let truncated_header () =
  (* nhttp-7pp8: EOF partway through either record-length byte is not normal EOF. *)
  List.iter (fun n -> damaged_record (fun wire -> Cstruct.sub wire 0 n)) [ 1; 3; 4 ]

let truncated_payload () =
  (* nhttp-7pp8: complete header, but missing ciphertext or authentication tag. *)
  damaged_record (fun wire -> Cstruct.sub wire 0 5);
  damaged_record (fun wire -> Cstruct.sub wire 0 (Cstruct.length wire - 1))

let corrupt_record () =
  (* nhttp-7pp8: a full, correctly framed record still must authenticate. *)
  damaged_record (fun wire ->
      let last = Cstruct.length wire - 1 in
      Cstruct.set_uint8 wire last (Cstruct.get_uint8 wire last lxor 1);
      wire)

let fragmented_record () =
  (* nhttp-7pp8: split headers and coalesced records both end at the same boundary. *)
  with_pair
    (fun raw ssl _ ->
      let wire = record ssl in
      for off = 0 to Cstruct.length wire - 1 do
        Eio.Flow.write raw [ Cstruct.sub wire off 1 ];
        Eio.Fiber.yield ()
      done;
      Eio.Flow.close raw)
    (fun _ _ flow ->
      read_message flow "next message";
      expect_eof flow)

let close_failure () =
  (* nhttp-rs5p: failure sending close_notify still releases the raw socket. *)
  with_pair
    (fun _ _ flow -> expect_eof flow)
    (fun raw _ flow ->
      Eio.Flow.shutdown raw `Send;
      (match Eio.Flow.close flow with
      | () -> Alcotest.fail "close_notify write unexpectedly succeeded"
      | exception Eio.Io _ -> ());
      Eio.Flow.close flow;
      match Eio.Flow.copy_string "x" raw with
      | () -> Alcotest.fail "raw socket remained open"
      | exception Invalid_argument _ -> ())

let close_cancelled () =
  (* nhttp-rs5p: cancellation during alert delivery still releases the socket. *)
  with_pair
    (fun _ _ flow -> expect_eof flow)
    (fun raw _ flow ->
      let cancelled =
        try
          Eio.Cancel.sub (fun cancel ->
              Eio.Cancel.cancel cancel Exit;
              Eio.Flow.close flow);
          false
        with Eio.Cancel.Cancelled _ -> true
      in
      Alcotest.(check bool) "alert write observes cancellation" true cancelled;
      Eio.Flow.close flow;
      match Eio.Flow.copy_string "x" raw with
      | () -> Alcotest.fail "cancelled close left the raw socket open"
      | exception Invalid_argument _ -> ())

let cases =
  [
    Alcotest.test_case "unnotified EOF drains complete records" `Quick unnotified_eof;
    Alcotest.test_case "server close_notify and socket close" `Quick server_close;
    Alcotest.test_case "client close_notify and socket close" `Quick client_close;
    Alcotest.test_case "truncated record header" `Quick truncated_header;
    Alcotest.test_case "truncated record payload" `Quick truncated_payload;
    Alcotest.test_case "corrupted complete record" `Quick corrupt_record;
    Alcotest.test_case "fragmented complete record" `Quick fragmented_record;
    Alcotest.test_case "failed alert still releases socket" `Quick close_failure;
    Alcotest.test_case "cancelled alert still releases socket" `Quick close_cancelled;
  ]
