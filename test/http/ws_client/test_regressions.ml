(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
module H = Ox_http
module W = H.Ws_client
module C = H.Ws_codec

let frame opcode payload =
  C.encode { C.fin = true; opcode; payload = Bytes.of_string payload } |> Bytes.to_string

let expect_ok = function
  | Ok value -> value
  | Error _ -> Alcotest.fail "unexpected WebSocket error"

(* The real public connect/send/receive paths, with scripted transport I/O.
   Each chunk owns its read boundary, so the clock changes before that frame. *)
module Script = struct
  type tag = [ `Generic ]

  type t = {
    mutable input : string;
    next : unit -> string;
    write : string -> unit;
    on_close : unit -> unit;
    mutable closed : bool;
  }

  let read_methods = []

  let single_read t buf =
    if t.input = "" then t.input <- t.next ();
    let n = min (String.length t.input) (Cstruct.length buf) in
    if n = 0 then raise End_of_file;
    Cstruct.blit_from_string t.input 0 buf 0 n;
    t.input <- String.sub t.input n (String.length t.input - n);
    n

  let single_write t bufs =
    t.write (String.concat "" (List.map Cstruct.to_string bufs));
    Cstruct.lenv bufs

  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
  let shutdown _ _ = ()
  let setsockopt _ _ _ = invalid_arg "scripted socket: no socket options"
  let getsockopt _ _ = invalid_arg "scripted socket: no socket options"

  let close t =
    if not t.closed then (
      t.closed <- true;
      t.on_close ())
end

let with_ws ?(on_close = fun () -> ()) next write test =
  Eio_mock.Backend.run_full (fun env ->
      Eio.Switch.run (fun sw ->
          let response = ref "" in
          let upgraded = ref false in
          let on_write text =
            if !upgraded then write text
            else
              let key =
                String.split_on_char '\n' text
                |> List.find_map (fun line ->
                    let prefix = "Sec-WebSocket-Key: " in
                    if String.starts_with ~prefix line then
                      Some
                        (String.trim
                           (String.sub line (String.length prefix)
                              (String.length line - String.length prefix)))
                    else None)
                |> function
                | Some key -> key
                | None -> Alcotest.fail "missing WebSocket upgrade key fixture"
              in
              response :=
                "HTTP/1.1 101 Switching Protocols\r\n\
                 Upgrade: websocket\r\n\
                 Connection: Upgrade\r\n\
                 Sec-WebSocket-Accept: "
                ^ C.accept_key ~sha1:H.Ox_http_tls_openssl.sha1 key
                ^ "\r\n\r\n";
              upgraded := true
          in
          let state =
            {
              Script.input = "";
              next =
                (fun () ->
                  if !response <> "" then (
                    let data = !response in
                    response := "";
                    data)
                  else next env#clock);
              write = on_write;
              on_close;
              closed = false;
            }
          in
          let flow = Eio.Resource.T (state, Eio.Net.Pi.stream_socket (module Script)) in
          let net = Eio_mock.Net.make "WebSocket regression" in
          Eio_mock.Net.on_getaddrinfo net
            [ `Return [ `Tcp (Eio.Net.Ipaddr.V4.loopback, 80) ] ];
          Eio_mock.Net.on_connect net [ `Return flow ];
          let ws = W.connect ~sw ~net ~clock:env#clock "ws://localhost/" |> expect_ok in
          test env#clock sw ws))

let check_pong expected text =
  match C.decode ~masked:true (Bytes.of_string text) with
  | Ok ({ opcode = C.Pong; payload; _ }, _) ->
      Alcotest.(check string) "pong payload" expected (Bytes.to_string payload)
  | _ -> Alcotest.fail "expected masked pong"

let check_tls = function
  | Error (`Tls "primary bad record mac") -> ()
  | _ -> Alcotest.fail "primary TLS failure was replaced"

let test_quiet_pings () =
  (* ^wsduplex-h6pk: one receive waits through 2,000 seconds, not 32 frames. *)
  let sent = ref 0 in
  let answered = ref 0 in
  with_ws
    (fun clock ->
      if !sent = 100 then frame C.Text "still alive"
      else (
        incr sent;
        Eio.Time.sleep clock 20.;
        frame C.Ping (string_of_int !sent)))
    (fun text ->
      incr answered;
      check_pong (string_of_int !answered) text)
    (fun clock _ ws ->
      Alcotest.(check bool)
        "quiet receive survives" true
        (W.receive ws = Ok (`Text "still alive"));
      Alcotest.(check int) "all keepalives answered" 100 !answered;
      Alcotest.(check (float 0.)) "mock elapsed seconds" 2000. (Eio.Time.now clock))

let test_burst opcode () =
  (* ^wsduplex-h6pk: both Ping and unsolicited Pong floods have a finite budget. *)
  let replies = ref 0 in
  with_ws
    (fun _ -> frame opcode "burst")
    (fun text ->
      incr replies;
      check_pong "burst" text)
    (fun _ _ ws ->
      match W.receive ws with
      | Error (`Protocol "too many control frames per second") ->
          Alcotest.(check int)
            "bounded replies"
            (if opcode = C.Ping then 32 else 0)
            !replies
      | _ -> Alcotest.fail "burst control flood did not fail")

let test_connection_budget () =
  (* ^wsduplex-h6pk: data/receive boundaries cannot hide a sustained flood. *)
  let ping = ref true in
  with_ws
    (fun _ ->
      let op = if !ping then C.Ping else C.Text in
      ping := not !ping;
      frame op "interleaved")
    (check_pong "interleaved")
    (fun clock _ ws ->
      for _ = 1 to 32 do
        ignore (W.receive ws |> expect_ok)
      done;
      Eio.Time.sleep clock 1.;
      for _ = 1 to 32 do
        ignore (W.receive ws |> expect_ok)
      done;
      match W.receive ws with
      | Error (`Protocol "too many control frames per second") -> ()
      | _ -> Alcotest.fail "receive calls reset the flood budget")

let test_primary_failure () =
  (* ^wsduplex-v8mq: sender sees the cause while receiver is parked in shutdown. *)
  let entered, signal = Eio.Promise.create () in
  let release, resume = Eio.Promise.create () in
  let sent = ref 0 in
  with_ws
    ~on_close:(fun () ->
      Eio.Promise.resolve signal ();
      Eio.Promise.await release)
    (fun _ -> raise (H.Tls_flow.Testing.failure "primary bad record mac"))
    (fun _ -> incr sent)
    (fun _ sw ws ->
      let received, resolve = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () -> Eio.Promise.resolve resolve (W.receive ws));
      Eio.Promise.await entered;
      check_tls (W.send_text ws "must not write");
      check_tls (W.send_binary ws Bytes.empty);
      check_tls (W.receive ws);
      check_tls (W.close ws);
      Alcotest.(check int) "no writes after failure" 0 !sent;
      Eio.Promise.resolve resume ();
      check_tls (Eio.Promise.await received);
      check_tls (W.send_text ws "after shutdown"))

let test_fail_fast_primary () =
  (* ^wsduplex-v8mq: secondary sender may win, but carries the original cause. *)
  let entered, signal = Eio.Promise.create () in
  with_ws
    ~on_close:(fun () ->
      Eio.Promise.resolve signal ();
      Eio.Fiber.await_cancel ())
    (fun _ -> raise (H.Tls_flow.Testing.failure "primary bad record mac"))
    (fun _ -> Alcotest.fail "sender wrote after transport failure")
    (fun _ sw ws ->
      check_tls
        (Ox.Concurrent.par ~sw
           (fun () -> W.receive ws)
           (fun () ->
             Eio.Promise.await entered;
             W.send_text ws "racing sender"));
      check_tls (W.receive ws);
      check_tls (W.send_text ws "after receiver cancellation"))

let test_abnormal_close_cause () =
  (* ^wsduplex-v8mq: EOF is abnormal termination, not a later normal close. *)
  with_ws
    (fun _ -> raise End_of_file)
    (fun _ -> Alcotest.fail "sender wrote after EOF")
    (fun _ _ ws ->
      let original = `Closed (1006, "unexpected EOF") in
      Alcotest.(check bool) "original EOF" true (W.receive ws = Error original);
      Alcotest.(check bool)
        "send retains EOF" true
        (W.send_text ws "after EOF" = Error original);
      Alcotest.(check bool) "close retains EOF" true (W.close ws = Error original))

let cases =
  [
    Alcotest.test_case "^wsduplex-h6pk quiet keepalive lifetime" `Quick test_quiet_pings;
    Alcotest.test_case "^wsduplex-h6pk ping flood" `Quick (test_burst C.Ping);
    Alcotest.test_case "^wsduplex-h6pk pong flood" `Quick (test_burst C.Pong);
    Alcotest.test_case "^wsduplex-h6pk connection elapsed budget" `Quick
      test_connection_budget;
    Alcotest.test_case "^wsduplex-v8mq parked shutdown cause" `Quick test_primary_failure;
    Alcotest.test_case "^wsduplex-v8mq fail-fast cause" `Quick test_fail_fast_primary;
    Alcotest.test_case "^wsduplex-v8mq abnormal-close cause" `Quick
      test_abnormal_close_cause;
  ]
