(* nhttp-7pp8 nhttp-rs5p wsduplex-j4rn: Pie's lifecycle_soak WSS fixture pulled row 38.
   Full-duplex coverage is the parked-read alias probe and the loopback stress. *)
module H = Ox_http
module S = H.Ox_http_tls_openssl

let local = Eio.Net.Ipaddr.V4.loopback

let with_pair ?(timeout = 5.) server client =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock timeout (fun () ->
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
  | exception exn when Option.is_some (H.Tls_flow.failure_message exn) ->
      let detail = Option.get (H.Tls_flow.failure_message exn) in
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

(* wsduplex-j4rn: the raw flow below Tls_flow. The first post-handshake read
   parks inside single_read with a canary in the caller's buffer; the write
   yields before touching the socket. Alias shows up as buffer identity or a
   destroyed canary. *)
module Probe = struct
  type state = {
    underlying : H.Tls_flow.ty Eio.Resource.t;
    mutable armed : bool;
    parked : Eio.Semaphore.t;
    release_read : Eio.Semaphore.t;
    mutable read_buffer : Cstruct.buffer option;
    mutable saw_write : bool;
    mutable aliased : bool;
    mutable write_stable : bool;
    mutable canary_intact : bool;
    mutable yields : int;
  }

  type t = state

  let canary = 0xA5

  let single_read t dst =
    if t.armed && Option.is_none t.read_buffer then (
      t.read_buffer <- Some (Cstruct.to_bigarray dst);
      Cstruct.memset dst canary;
      Eio.Semaphore.release t.parked;
      Eio.Semaphore.acquire t.release_read;
      let intact = ref true in
      for i = 0 to Cstruct.length dst - 1 do
        if Cstruct.get_uint8 dst i <> canary then intact := false
      done;
      t.canary_intact <- !intact;
      Eio.Flow.single_read t.underlying dst)
    else Eio.Flow.single_read t.underlying dst

  let single_write t bufs =
    match bufs with
    | first :: _ when t.armed && Option.is_some t.read_buffer && not t.saw_write ->
        t.saw_write <- true;
        (match t.read_buffer with
        | Some buf when buf == Cstruct.to_bigarray first -> t.aliased <- true
        | _ -> ());
        let before = Cstruct.to_string first in
        for _ = 1 to 8 do
          Eio.Fiber.yield ();
          t.yields <- t.yields + 1
        done;
        if Cstruct.to_string first <> before then t.write_stable <- false;
        let n = Eio.Flow.single_write t.underlying bufs in
        Eio.Semaphore.release t.release_read;
        n
    | _ -> Eio.Flow.single_write t.underlying bufs

  let shutdown t command = Eio.Flow.shutdown t.underlying command
  let close t = Eio.Flow.close t.underlying

  module Pi = struct
    type nonrec t = t

    let read_methods = []
    let single_read = single_read
    let single_write = single_write
    let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
    let shutdown = shutdown
  end

  let wrap underlying =
    let state =
      {
        underlying;
        armed = false;
        parked = Eio.Semaphore.make 0;
        release_read = Eio.Semaphore.make 0;
        read_buffer = None;
        saw_write = false;
        aliased = false;
        write_stable = true;
        canary_intact = false;
        yields = 0;
      }
    in
    let handler : (state, H.Tls_flow.ty) Eio.Resource.handler =
      Eio.Resource.handler
        (Eio.Resource.H (Eio.Resource.Close, close)
        :: Eio.Resource.bindings (Eio.Flow.Pi.two_way (module Pi)))
    in
    (state, Eio.Resource.T (state, handler))
end

let with_probed_pair ?(timeout = 5.) server client =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock timeout (fun () ->
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
                  server flow)
                (fun () ->
                  let raw = Eio.Net.connect ~sw env#net address in
                  let state, probed = Probe.wrap (raw :> H.Tls_flow.ty Eio.Resource.t) in
                  let ctx = S.create_ctx () in
                  S.ctx_load_ca ctx "localhost.crt";
                  let ssl =
                    S.create_ssl ctx ~hostname:(Some "localhost") ~ip:None
                      ~alpn_protocols:[ "http/1.1" ]
                  in
                  let flow = H.Tls_flow.create ~raw:probed ~ssl in
                  client sw state flow))))

let parked_read_yielding_write () =
  (* wsduplex-j4rn: the read is inside raw single_read before the write runs,
     and the write yields before the read is released. A shared buffer deadlocks
     or fails the canary; a correct send still arrives intact. *)
  with_probed_pair
    (fun flow ->
      read_message flow "ping";
      Eio.Flow.copy_string "pong" flow)
    (fun _sw state flow ->
      state.armed <- true;
      Eio.Fiber.both
        (fun () -> read_message flow "pong")
        (fun () ->
          Eio.Semaphore.acquire state.parked;
          Eio.Flow.copy_string "ping" flow);
      Alcotest.(check bool) "write ran during parked read" true state.saw_write;
      Alcotest.(check bool) "write yielded while read was parked" true (state.yields >= 8);
      Alcotest.(check bool) "ciphertext buffers do not alias" false state.aliased;
      Alcotest.(check bool) "write bytes stable across yields" true state.write_stable;
      Alcotest.(check bool) "parked read buffer untouched" true state.canary_intact)

let duplex_messages =
  List.init 60 (fun i ->
      let len =
        match i mod 5 with 0 -> 1 | 1 -> 64 | 2 -> 4096 | 3 -> 16384 | _ -> 40000
      in
      String.init len (fun j -> Char.chr (33 + ((i + j) mod 90))))

let exchange flow messages =
  let send () =
    List.iter
      (fun message ->
        Eio.Fiber.yield ();
        Eio.Flow.copy_string message flow)
      messages
  in
  let recv () = List.iter (fun message -> read_message flow message) messages in
  Eio.Fiber.both send recv

let duplex_stress () =
  (* wsduplex-j4rn: concurrent send and receive, both directions, including
     multi-record payloads. A shared ciphertext buffer surfaces as a bad record MAC. *)
  with_pair ~timeout:15.
    (fun _ _ flow -> exchange flow duplex_messages)
    (fun _ _ flow -> exchange flow duplex_messages)

let frame i = Printf.sprintf "%08d" i
let framed count = String.concat "" (List.init count frame)

let is_subsequence haystack needle =
  let i = ref 0 in
  let j = ref 0 in
  while !i < String.length haystack && !j < String.length needle do
    if haystack.[!i] = needle.[!j] then incr j;
    incr i
  done;
  !j = String.length needle

let frame_b i =
  Printf.sprintf "%08x" i
  |> String.map (fun c ->
      if c >= '0' && c <= '9' then Char.chr (Char.code c - Char.code '0' + Char.code 'A')
      else Char.chr (Char.code c - Char.code 'a' + Char.code 'K'))

let concurrent_writers () =
  (* wsduplex-j4rn: two writers must not byte-interleave ciphertext. Alphabets
     do not overlap, so each payload's increasing frames must stay in order. *)
  let left = framed 4000 in
  let right = String.concat "" (List.init 4000 frame_b) in
  with_pair ~timeout:10.
    (fun _ _ flow ->
      let got = Cstruct.create (String.length left + String.length right) in
      Eio.Flow.read_exact flow got;
      let got = Cstruct.to_string got in
      Alcotest.(check int)
        "both payloads"
        (String.length left + String.length right)
        (String.length got);
      Alcotest.(check bool) "left writer order preserved" true (is_subsequence got left);
      Alcotest.(check bool) "right writer order preserved" true (is_subsequence got right))
    (fun _ _ flow ->
      Eio.Fiber.both
        (fun () -> Eio.Flow.copy_string left flow)
        (fun () -> Eio.Flow.copy_string right flow))

let cancel_parked_read () =
  (* wsduplex-j4rn: cancelling the parked read unlocks rather than poisoning,
     and a later send is not stuck behind that read. *)
  with_probed_pair
    (fun flow ->
      read_message flow "after-cancel";
      Eio.Flow.copy_string "ok" flow)
    (fun sw state flow ->
      state.armed <- true;
      let cancel_read = ref None in
      let finished = Eio.Semaphore.make 0 in
      Eio.Fiber.fork ~sw (fun () ->
          (try
             Eio.Cancel.sub (fun cancel ->
                 cancel_read := Some cancel;
                 ignore (Eio.Flow.single_read flow (Cstruct.create 8)))
           with Eio.Cancel.Cancelled _ -> ());
          Eio.Semaphore.release finished);
      Eio.Semaphore.acquire state.parked;
      (match !cancel_read with
      | None -> Alcotest.fail "parked read did not publish its cancel"
      | Some cancel -> Eio.Cancel.cancel cancel Exit);
      Eio.Semaphore.acquire finished;
      state.armed <- false;
      Eio.Flow.copy_string "after-cancel" flow;
      read_message flow "ok")

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
    Alcotest.test_case "parked read and yielding write do not alias" `Quick
      parked_read_yielding_write;
    Alcotest.test_case "concurrent writers keep wire order" `Quick concurrent_writers;
    Alcotest.test_case "cancelled parked read does not stick the writer" `Quick
      cancel_parked_read;
    Alcotest.test_case "full-duplex loopback has no MAC failure" `Quick duplex_stress;
  ]
