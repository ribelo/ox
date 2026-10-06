(* ^nstress-0uv9. Libraries: stress_support ox_http ox_test eio eio_main eio.mock unix. *)
module C = Ox_http.Ws_codec
module W = Ox_http.Ws_client

(* ^safe-p9cw: elapsed assertions share the operation’s monotonic clock. *)
let elapsed clock start =
  Mtime.Span.to_float_ns (Mtime.span start (Eio.Time.Mono.now clock)) /. 1e9

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "%s" label

let fd_count ~(caps : < Ox_caps.Cap.fs_read ; .. >) () =
  Array.length (Ox_caps.Cap_sys.readdir ~caps "/proc/self/fd")

let flood_error = `Protocol "too many control frames per second"

let expect_ok = function
  | Ok value -> value
  | Error _ -> fail "WebSocket operation unexpectedly failed"

let frame opcode payload =
  C.encode { C.fin = true; opcode; payload = Bytes.of_string payload } |> Bytes.to_string

let read_frame input =
  let head = Eio.Buf_read.take 2 input in
  let length = Char.code head.[1] land 127 in
  let extra = if length = 126 then 2 else if length = 127 then 8 else 0 in
  let extended = Eio.Buf_read.take extra input in
  let length =
    if extra = 0 then length
    else if extra = 2 then Bytes.get_uint16_be (Bytes.of_string extended) 0
    else Int64.to_int (Bytes.get_int64_be (Bytes.of_string extended) 0)
  in
  check "server received an unmasked frame" (Char.code head.[1] land 128 <> 0);
  check "unexpectedly large client frame" (length <= 4096);
  let rest = Eio.Buf_read.take (4 + length) input in
  match C.decode ~masked:true (Bytes.of_string (head ^ extended ^ rest)) with
  | Ok (frame, _) -> frame
  | Error _ -> fail "invalid masked frame from Ws_client"

let upgrade flow =
  let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
  check "bad loopback upgrade request" (Eio.Buf_read.line input = "GET /stress HTTP/1.1");
  let rec headers key =
    match Eio.Buf_read.line input with
    | "" -> key
    | line ->
        let colon = String.index line ':' in
        let name = String.lowercase_ascii (String.sub line 0 colon) in
        let value =
          String.trim (String.sub line (colon + 1) (String.length line - colon - 1))
        in
        headers (if name = "sec-websocket-key" then value else key)
  in
  let key = headers "" in
  check "missing WebSocket key" (key <> "");
  let accept = C.accept_key ~sha1:Ox_http.Ox_http_tls_openssl.sha1 key in
  Eio.Flow.copy_string
    ("HTTP/1.1 101 Switching Protocols\r\n\
      Upgrade: websocket\r\n\
      Connection: Upgrade\r\n\
      Sec-WebSocket-Accept: " ^ accept ^ "\r\n\r\n")
    flow;
  input

(* Only the dial capability is scripted: both returned endpoints are real TCP
   loopback sockets. Keeping the client's raw endpoint lets us half-close it
   without reaching into Ws_client's abstract connection. *)
let with_pair ~(caps : < Ox_caps.Cap.stderr ; .. >) ?(timeout = 2.) env f =
  let finished = ref false in
  let leaked =
    Ox_test.with_census (fun () ->
        Eio.Time.with_timeout_exn env#clock timeout (fun () ->
            Eio.Switch.run (fun sw ->
                let listener =
                  Eio.Net.listen ~sw ~backlog:2 env#net
                    (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
                in
                let address = Eio.Net.listening_addr listener in
                let raw = Eio.Net.connect ~sw env#net address in
                let accepted, resolve = Eio.Promise.create () in
                Eio.Fiber.fork ~sw (fun () ->
                    let server, _ = Eio.Net.accept ~sw listener in
                    let input = upgrade server in
                    Eio.Promise.resolve resolve (server, input));
                let net = Eio_mock.Net.make "live loopback ws dial" in
                Eio_mock.Net.on_getaddrinfo net
                  [ `Return [ (address :> Eio.Net.Sockaddr.t) ] ];
                Eio_mock.Net.on_connect net [ `Return raw ];
                let quiet_trace =
                  {
                    Eio.Debug.traceln =
                      (fun ?__POS__:_ fmt ->
                        Format.ifprintf (Ox_caps.Cap_stdlib.err_formatter ~caps) fmt);
                  }
                in
                let ws =
                  Eio.Fiber.with_binding (Eio.Stdenv.debug env)#traceln quiet_trace
                    (fun () ->
                      W.connect ~sw ~net ~clock:env#mono_clock "ws://127.0.0.1/stress")
                  |> expect_ok
                in
                let server, input = Eio.Promise.await accepted in
                f sw ws raw server input));
        finished := true)
  in
  check "WebSocket switch did not finish" !finished;
  check "WebSocket pair leaked fibers" (leaked = 0)

let drain input observe =
  let rec loop () =
    let frame = read_frame input in
    observe frame;
    loop ()
  in
  try loop () with End_of_file | Eio.Io _ -> ()

let quiet ~(caps : < Ox_caps.Cap.stderr ; .. >) env =
  (* More than 32 pings over one receive: quiet keepalives have no lifetime cap. *)
  with_pair ~caps ~timeout:6. env (fun sw ws _ server input ->
      let pongs = ref 0 and texts = ref 0 in
      Eio.Fiber.fork ~sw (fun () ->
          drain input (fun frame ->
              match frame.C.opcode with
              | Pong ->
                  check "quiet pong payload/order"
                    (Bytes.to_string frame.payload = string_of_int !pongs);
                  incr pongs
              | Text -> incr texts
              | Close -> ()
              | _ -> fail "unexpected quiet client opcode"));
      Eio.Fiber.fork ~sw (fun () ->
          for i = 0 to 47 do
            Eio.Flow.copy_string (frame C.Ping (string_of_int i)) server;
            Eio.Time.sleep env#clock 0.065
          done;
          Eio.Flow.copy_string (frame C.Text "quiet survived") server);
      Eio.Fiber.fork ~sw (fun () ->
          for _ = 1 to 48 do
            W.send_text ws "full duplex" |> expect_ok;
            Eio.Time.sleep env#clock 0.03
          done);
      check "quiet receive ended prematurely" (W.receive ws = Ok (`Text "quiet survived"));
      W.close ws |> expect_ok;
      (* The drain fiber is joined by with_pair before counters are inspected. *)
      Eio.Switch.on_release sw (fun () ->
          check "quiet ping replies lost" (!pongs = 48);
          check "full-duplex sends lost" (!texts = 48)))

let flood ~(caps : < Ox_caps.Cap.stderr ; .. >) env opcode interleaved =
  let processed = ref 0 and pongs = ref 0 in
  let started = Eio.Time.Mono.now env#mono_clock in
  with_pair ~caps env (fun sw ws _ server input ->
      let payload = "flood" in
      let packet =
        String.concat ""
          (List.init 512 (fun _ ->
               frame opcode payload ^ if interleaved then frame C.Text "boundary" else ""))
      in
      Eio.Fiber.fork ~sw (fun () ->
          drain input (fun frame ->
              match frame.C.opcode with
              | Pong ->
                  check "flood pong payload" (Bytes.to_string frame.payload = payload);
                  incr pongs
              | _ -> fail "unexpected client frame during flood"));
      Eio.Fiber.fork ~sw (fun () ->
          try Eio.Flow.copy_string packet server with Eio.Io _ | End_of_file -> ());
      let rec receive () =
        match W.receive ws with
        | Ok (`Text "boundary") when interleaved ->
            incr processed;
            receive ()
        | Error error when error = flood_error -> ()
        | _ -> fail "live control flood did not return row-57 budget error"
      in
      receive ();
      let elapsed = max 0. (elapsed env#mono_clock started) in
      let bound = 32 + int_of_float (ceil (32. *. elapsed)) in
      check "receive-call boundaries reset the timed control budget" (!processed <= bound);
      check "flood receiver did no work" ((not interleaved) || !processed > 0);
      check "terminal flood cause was not retained"
        (W.send_text ws "after flood" = Error flood_error);
      check "close hid the primary flood cause" (W.close ws = Error flood_error);
      Eio.Switch.on_release sw (fun () ->
          check "ping replies exceeded the elapsed-time bucket" (!pongs <= bound);
          check "ping flood was not answered" (opcode <> C.Ping || !pongs > 0);
          check "unsolicited pongs produced replies" (opcode <> C.Pong || !pongs = 0)));
  !processed

let half_close ~(caps : < Ox_caps.Cap.stderr ; .. >) env random =
  with_pair ~caps env (fun sw ws raw server input ->
      let count = 8 + Random.State.int random 16 in
      let ready, signal = Eio.Promise.create () in
      let sent, done_sending = Eio.Promise.create () in
      let client_cut = ref false and server_cut = ref false and received = ref 0 in
      Eio.Fiber.fork ~sw (fun () ->
          drain input (fun frame ->
              match frame.C.opcode with
              | Text -> incr received
              | _ -> fail "unexpected half-close client frame"));
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Flow.copy_string
            (String.concat "" (List.init count (fun _ -> frame C.Ping "half-close")))
            server;
          Eio.Promise.resolve signal ());
      Eio.Fiber.fork ~sw (fun () ->
          for _ = 1 to count do
            W.send_text ws "in flight" |> expect_ok
          done;
          Eio.Promise.resolve done_sending ());
      Eio.Promise.await ready;
      Eio.Promise.await sent;
      (* Same barrier, opposite TCP send directions, with keepalives and data
         already in flight. Do not close the owning switch to rescue the pair. *)
      let cut flow flag () =
        Eio.Flow.shutdown flow `Send;
        flag := true
      in
      let client () = cut raw client_cut () and peer () = cut server server_cut () in
      if Random.State.bool random then Eio.Fiber.both client peer
      else Eio.Fiber.both peer client;
      (match W.receive ws with
      | Error (`Closed _) -> ()
      | _ -> fail "simultaneous half-close did not cleanly terminate receive");
      Eio.Switch.on_release sw (fun () ->
          check "both endpoints must half-close" (!client_cut && !server_cut);
          check "in-flight client messages lost before half-close" (!received = count)))

let run
    ~(caps :
       < Ox_caps.Cap.env
       ; Ox_caps.Cap.stdout
       ; Ox_caps.Cap.stderr
       ; Ox_caps.Cap.fs_read
       ; .. >) () =
  let random = Stress_support.random ~caps ~default:60057 () in
  Eio_main.run (fun env ->
      (* Establish scheduler resources before taking the descriptor baseline. *)
      Eio.Time.sleep env#clock 0.001;
      with_pair ~caps env (fun _ ws _ _ _ -> W.close ws |> expect_ok);
      let before = fd_count ~caps () in
      let rounds = ref 0 in
      Eio.Time.with_timeout_exn env#clock 50. (fun () ->
          let deadline =
            Mtime.add_span
              (Eio.Time.Mono.now env#mono_clock)
              (Mtime.Span.of_uint64_ns 30_000_000_000L)
            |> Option.get
          in
          quiet ~caps env;
          while Mtime.is_earlier (Eio.Time.Mono.now env#mono_clock) ~than:deadline do
            ignore (flood ~caps env C.Ping (Random.State.bool random));
            ignore (flood ~caps env C.Pong true);
            half_close ~caps env random;
            incr rounds;
            Eio.Time.sleep env#clock 0.01
          done);
      check "no storm rounds executed" (!rounds > 0);
      check "WebSocket storm leaked descriptors" (fd_count ~caps () = before);
      Ox_caps.Cap_stdlib.printf ~caps
        "ws_storm: 30s, %d flood/half-close rounds; fibers and fds released\n%!" !rounds)

let () = run ~caps:(Ox_test.powerbox ()) ()
