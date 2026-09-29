module C = Ox_http.Ws_codec

let byte_list xs = Bytes.init (List.length xs) (fun i -> Char.chr (List.nth xs i))

let test_vectors () =
  (* Copied from v1's RFC 6455 codec acceptance / masking cases. ^nws-d5r1 *)
  Alcotest.(check string)
    "RFC accept" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    (C.accept_key ~sha1:Ox_http.Ox_http_tls_openssl.sha1 "dGhlIHNhbXBsZSBub25jZQ==");
  Alcotest.(check string)
    "nonce" "dGhlIHNhbXBsZSBub25jZQ=="
    (C.key_of_nonce (Bytes.of_string "the sample nonce"));
  let frame = { C.fin = true; opcode = Text; payload = Bytes.of_string "Hello" } in
  Alcotest.(check string)
    "RFC masked frame" "81 85 37 fa 21 3d 7f 9f 4d 51 58"
    (C.encode ~mask:(byte_list [ 0x37; 0xfa; 0x21; 0x3d ]) frame
    |> Bytes.to_seq |> List.of_seq
    |> List.map (fun c -> Printf.sprintf "%02x" (Char.code c))
    |> String.concat " ");
  (match C.decode ~masked:true (C.encode ~mask:(Bytes.of_string "abcd") frame) with
  | Ok (decoded, 11) when decoded = frame -> ()
  | _ -> Alcotest.fail "masked codec roundtrip");
  match C.decode (C.encode frame) with
  | Ok (decoded, 7) when decoded = frame -> ()
  | _ -> Alcotest.fail "unmasked codec roundtrip"

let test_boundaries () =
  (* v1 length/control/close rejection cases. ^nws-d5r1 *)
  List.iter
    (fun len ->
      let frame = { C.fin = true; opcode = Binary; payload = Bytes.make len 'x' } in
      match C.decode (C.encode frame) with
      | Ok (got, consumed) ->
          Alcotest.(check int) "payload size" len (Bytes.length got.payload);
          Alcotest.(check int) "consumed" (Bytes.length (C.encode frame)) consumed
      | Error _ -> Alcotest.fail "length boundary failed")
    [ 0; 125; 126; 65535; 65536 ];
  let bad input expected =
    match C.decode (byte_list input) with
    | Error got when got = expected -> ()
    | _ -> Alcotest.fail "expected codec rejection"
  in
  bad [ 0x89; 0x7e; 0; 126 ] C.Control_payload_too_large;
  bad [ 0x09; 0 ] C.Control_fragmented;
  bad [ 0x88; 1; 0 ] C.Invalid_close_payload;
  bad [ 0x88; 2; 0x03; 0xed ] C.Invalid_close_code;
  bad [ 0x81; 0x7e; 0; 125 ] C.Non_minimal_length;
  bad [ 0xc1; 0 ] C.Reserved_bits;
  bad [ 0x81; 0x80; 0; 0; 0; 0 ] C.Mask_forbidden;
  match C.decode ~masked:true (byte_list [ 0x81; 0 ]) with
  | Error C.Mask_required -> ()
  | _ -> Alcotest.fail "mask required"

let cases =
  [
    Alcotest.test_case "^nws-d5r1 v1 RFC and masking vectors" `Quick test_vectors;
    Alcotest.test_case "^nws-d5r1 v1 lengths and invalid controls" `Quick test_boundaries;
  ]
