module L = Ox_ipc.Listener

let fail fmt = Alcotest.failf fmt
let check_ok = function Ok () -> () | Error _ -> fail "listener acquisition failed"

let exists p =
  match Unix.lstat p with
  | _ -> true
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> false

let with_dir f =
  let dir = Filename.temp_file ~temp_dir:"/tmp" "ip" "" in
  Unix.unlink dir;
  Unix.mkdir dir 0o700;
  Fun.protect
    ~finally:(fun () ->
      let rec clean path =
        if (Unix.lstat path).st_kind = Unix.S_DIR then (
          Array.iter (fun name -> clean (Filename.concat path name)) (Sys.readdir path);
          Unix.rmdir path)
        else Unix.unlink path
      in
      clean dir)
    (fun () -> f dir (dir ^ "/s"))

let start ?policy ?on_peer_error ?on_budget_exceeded ?error_response
    ?(decode = fun s -> Ok s) ?(budget = fun _ -> None) ?(handler = fun x -> Ok x) env sw
    path =
  L.run ~sw ~fs:env#fs ~net:env#net ~clock:env#clock ~path ?policy ~decode ~encode:Fun.id
    ~budget ~handler ?on_budget_exceeded ?error_response ?on_peer_error ()

let client env sw path = Eio.Net.connect ~sw env#net (`Unix path)

let request env sw path data =
  let flow = client env sw path in
  Eio.Flow.copy_string data flow;
  Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:65536 flow)

let check_error name expected actual =
  Alcotest.(check bool) name true (actual = Error expected)

let ownership () =
  (* nipc-tafd nipc-4kuy nipc-vayc nipc-f264 nipc-uatz *)
  with_dir (fun dir path ->
      Ox_test.run (fun env _ ->
          let nested = dir ^ "/private/s" in
          Eio.Switch.run (fun sw ->
              check_ok (start env sw nested);
              Alcotest.(check int)
                "private parent" 0o700
                ((Unix.stat (dir ^ "/private")).st_perm land 0o777);
              Alcotest.(check int)
                "private socket" 0o600
                ((Unix.stat nested).st_perm land 0o777));
          Alcotest.(check bool) "retired socket" false (exists nested);
          Unix.chmod dir 0o750;
          Eio.Switch.run (fun sw ->
              check_error "unsafe directory" `Unsafe_runtime_dir (start env sw path));
          Unix.chmod dir 0o700;
          let oc = open_out path in
          output_string oc "sentinel";
          close_out oc;
          Eio.Switch.run (fun sw ->
              match start env sw path with
              | Error (`Ownership_conflict path) -> ()
              | _ -> fail "regular file overwritten");
          let ic = open_in path in
          let text = input_line ic in
          close_in ic;
          Alcotest.(check string) "sentinel preserved" "sentinel" text;
          Unix.unlink path;
          Unix.symlink "missing" path;
          Eio.Switch.run (fun sw ->
              match start env sw path with
              | Error (`Ownership_conflict path) -> ()
              | _ -> fail "symlink followed");
          Unix.unlink path;
          let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
          Unix.bind fd (Unix.ADDR_UNIX path);
          Unix.close fd;
          Eio.Switch.run (fun sw ->
              check_ok (start env sw path);
              Alcotest.(check string)
                "stale socket replaced by live listener" "probe"
                (request env sw path "probe\n"));
          Alcotest.(check bool) "stale retired" false (exists path)))

let live_and_replacement () =
  (* nipc-4kuy nipc-vayc nipc-uatz *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          Eio.Switch.run (fun sw ->
              check_ok (start env sw path);
              Eio.Switch.run (fun competing ->
                  check_error "same-process registry" `Lock_conflict
                    (start env competing path));
              Alcotest.(check string)
                "survivor serves" "ping"
                (request env sw path "ping\n");
              let old = Unix.stat path in
              Unix.unlink path;
              let oc = open_out path in
              output_string oc "replacement";
              close_out oc;
              Alcotest.(check bool)
                "replacement identity differs" true
                ((Unix.stat path).st_ino <> old.st_ino));
          Alcotest.(check bool) "replacement retained" true (exists path)))

let line_and_policy () =
  (* nipc-skdt nipc-x8ph nipc-eiy8 nipc-ajmi nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let policy =
            { L.default_policy with max_line_bytes = 4; max_reply_bytes = 4; peers = 1 }
          in
          let errors = ref [] in
          let oversized, signal_oversized = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~on_peer_error:(fun x ->
                     errors := x :: !errors;
                     if x = `Ingress_too_large then
                       Eio.Promise.resolve signal_oversized ())
                   env sw path);
              Alcotest.(check string)
                "newline reply" "abcd"
                (request env sw path "abcd\n");
              let flow = client env sw path in
              Eio.Flow.copy_string "abcde\n" flow;
              Eio.Promise.await oversized;
              Alcotest.(check bool)
                "oversized ingress refused" true
                (List.mem `Ingress_too_large !errors));
          Alcotest.(check bool) "endpoint unlinked" false (exists path)))

let deadlines () =
  (* nipc-x8ph nipc-6i86 nipc-eiy8 nipc-1v8z *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let errors = ref [] and cleaned = ref false in
          let started, signal_started = Eio.Promise.create () in
          let budget_done, signal_budget_done = Eio.Promise.create () in
          let ingress_done, signal_ingress_done = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~budget:(fun _ -> Some (Ox.Duration.seconds 2))
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_started ();
                     Fun.protect
                       ~finally:(fun () -> cleaned := true)
                       (fun () ->
                         Eio.Time.sleep env#clock 100.;
                         Ok "late"))
                   ~on_peer_error:(fun e ->
                     errors := e :: !errors;
                     if e = `Handler_budget_exceeded then
                       Eio.Promise.resolve signal_budget_done ();
                     if e = `Ingress_timeout then
                       Eio.Promise.resolve signal_ingress_done ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "go\n" flow;
              Eio.Promise.await started;
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await budget_done;
              Alcotest.(check bool) "budget cancels handler" true !cleaned;
              Alcotest.(check bool)
                "typed budget" true
                (List.mem `Handler_budget_exceeded !errors);
              let stalled = client env sw path in
              Eio.Flow.copy_string "partial" stalled;
              Eio.Fiber.yield ();
              Eio.Fiber.yield ();
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await ingress_done;
              Alcotest.(check bool)
                "typed ingress" true
                (List.mem `Ingress_timeout !errors))))

let disconnect () =
  (* nipc-1v8z nipc-uatz nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let entered, signal_entered = Eio.Promise.create () in
          let left, signal_left = Eio.Promise.create () in
          let disconnected, signal_disconnect = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_entered ();
                     Fun.protect
                       ~finally:(fun () -> Eio.Promise.resolve signal_left ())
                       (fun () ->
                         Eio.Time.sleep env#clock 100.;
                         Ok "too late"))
                   ~on_peer_error:(function
                     | `Disconnected -> Eio.Promise.resolve signal_disconnect () | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "wait\n" flow;
              Eio.Promise.await entered;
              Eio.Flow.close flow;
              Eio.Promise.await disconnected;
              Eio.Promise.await left;
              Alcotest.(check bool) "listener still active" true (exists path));
          Alcotest.(check bool) "retired after disconnect" false (exists path)))

let saturated () =
  (* nipc-skdt nipc-6i86 nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let first, signal_first = Eio.Promise.create () in
          let release, signal_release = Eio.Promise.create () in
          let count = ref 0 in
          Eio.Switch.run (fun sw ->
              let policy = { L.default_policy with peers = 1; backlog = 1 } in
              check_ok
                (start ~policy
                   ~handler:(fun x ->
                     incr count;
                     if !count = 1 then (
                       Eio.Promise.resolve signal_first ();
                       Eio.Promise.await release);
                     Ok x)
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "one\n" flow;
              Eio.Promise.await first;
              let second = client env sw path in
              Eio.Flow.copy_string "two\n" second;
              Eio.Fiber.yield ();
              Alcotest.(check int) "only one handler admitted" 1 !count;
              Eio.Promise.resolve signal_release ();
              Alcotest.(check string)
                "second served after release" "two"
                (Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:32 second));
              Alcotest.(check int) "second handler admitted" 2 !count)))

let reply_bound () =
  (* nipc-eiy8 nipc-ajmi nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let rejected, signal_rejected = Eio.Promise.create () in
          let policy = { L.default_policy with max_reply_bytes = 4 } in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~handler:(fun x -> Ok (if x = "large" then "oversize" else x))
                   ~on_peer_error:(function
                     | `Egress_too_large -> Eio.Promise.resolve signal_rejected ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "ok\nextra\n" flow;
              let reader = Eio.Buf_read.of_flow ~max_size:64 flow in
              Alcotest.(check string) "single reply" "ok" (Eio.Buf_read.line reader);
              Alcotest.(check bool)
                "one reply then EOF" true
                (match Eio.Buf_read.line reader with
                | _ -> false
                | exception End_of_file -> true);
              let large = client env sw path in
              Eio.Flow.copy_string "large\n" large;
              Eio.Promise.await rejected)))

let cross_process () =
  (* nipc-4kuy nipc-vayc nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          Eio.Switch.run (fun sw ->
              check_ok (start env sw path);
              Eio.Process.run env#process_mgr
                [ Sys.executable_name; "--check-lock"; path ];
              Alcotest.(check string)
                "survives child lock contention" "ok" (request env sw path "ok\n"))))

let live_external () =
  (* nipc-4kuy nipc-vayc nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
          Fun.protect
            ~finally:(fun () -> Unix.close fd)
            (fun () ->
              Unix.bind fd (Unix.ADDR_UNIX path);
              Unix.listen fd 1;
              Eio.Switch.run (fun sw ->
                  check_error "active external listener" `Active_listener
                    (start env sw path));
              Alcotest.(check bool) "external endpoint preserved" true (exists path))))

let shutdown_active () =
  (* nipc-uatz nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let started, signal_started = Eio.Promise.create () in
          let cancelled = ref false in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~handler:(fun _ ->
                     Fun.protect
                       ~finally:(fun () -> cancelled := true)
                       (fun () ->
                         Eio.Promise.resolve signal_started ();
                         Eio.Time.sleep env#clock 100.;
                         Ok "late"))
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "wait\n" flow;
              Eio.Promise.await started);
          Alcotest.(check bool) "active peer cancelled and joined" true !cancelled;
          Alcotest.(check bool) "endpoint retired" false (exists path)))

let egress_timeout () =
  (* nipc-eiy8 nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let entered, signal_entered = Eio.Promise.create () in
          let timed_out, signal_timed_out = Eio.Promise.create () in
          let payload = String.make 8_000_000 'x' in
          let policy =
            { L.default_policy with max_reply_bytes = String.length payload }
          in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_entered ();
                     Ok payload)
                   ~on_peer_error:(function
                     | `Egress_timeout -> Eio.Promise.resolve signal_timed_out ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "flood\n" flow;
              Eio.Promise.await entered;
              Eio.Fiber.yield ();
              Eio.Fiber.yield ();
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await timed_out)))

let unbounded_budget () =
  (* nipc-6i86 nipc-01bn *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let entered, signal_entered = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_entered ();
                     Eio.Time.sleep env#clock 20.;
                     Ok "eventual")
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "handoff\n" flow;
              Eio.Promise.await entered;
              Ox_test.advance env#clock (Ox.Duration.seconds 25);
              Alcotest.(check string)
                "None budget permits long work" "eventual"
                (Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:32 flow)))))

let budget_reply () =
  (* nipc-i5ni nipc-6i86 nipc-eiy8 nipc-ajmi *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let started, signal_started = Eio.Promise.create () in
          let cut, signal_cut = Eio.Promise.create () in
          let handled = ref false in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~budget:(fun _ -> Some (Ox.Duration.seconds 2))
                   ~on_budget_exceeded:(fun request d ->
                     Printf.sprintf "timeout %s %d" request (Ox.Duration.to_ms d))
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_started ();
                     Fun.protect
                       ~finally:(fun () -> handled := true)
                       (fun () ->
                         Eio.Time.sleep env#clock 100.;
                         Ok "late"))
                   ~on_peer_error:(function
                     | `Handler_budget_exceeded -> Eio.Promise.resolve signal_cut ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "slow\n" flow;
              Eio.Promise.await started;
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await cut;
              Alcotest.(check bool) "handler cancelled at its budget" true !handled;
              let reader = Eio.Buf_read.of_flow ~max_size:64 flow in
              Alcotest.(check string)
                "chosen reply names the request and the budget" "timeout slow 2000"
                (Eio.Buf_read.line reader);
              Alcotest.(check bool)
                "one reply then close" true
                (match Eio.Buf_read.line reader with
                | _ -> false
                | exception End_of_file -> true))))

let budget_reply_byte_bound () =
  (* nipc-i5ni nipc-eiy8 *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let errors = ref [] in
          let started, signal_started = Eio.Promise.create () in
          let cut, signal_cut = Eio.Promise.create () in
          let rejected, signal_rejected = Eio.Promise.create () in
          let policy = { L.default_policy with max_reply_bytes = 4 } in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~budget:(fun _ -> Some (Ox.Duration.seconds 2))
                   ~on_budget_exceeded:(fun _ _ -> "oversize")
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_started ();
                     Eio.Time.sleep env#clock 100.;
                     Ok "late")
                   ~on_peer_error:(fun e ->
                     errors := e :: !errors;
                     if e = `Handler_budget_exceeded then
                       Eio.Promise.resolve signal_cut ();
                     if e = `Egress_too_large then Eio.Promise.resolve signal_rejected ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "big\n" flow;
              Eio.Promise.await started;
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await cut;
              Eio.Promise.await rejected;
              Alcotest.(check bool)
                "both the cut and the refused reply are typed" true
                (List.mem `Handler_budget_exceeded !errors
                && List.mem `Egress_too_large !errors);
              Alcotest.(check bool)
                "no reply, connection closed" true
                (match Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:64 flow) with
                | _ -> false
                | exception End_of_file -> true))))

let budget_reply_egress_deadline () =
  (* nipc-i5ni nipc-eiy8 *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let started, signal_started = Eio.Promise.create () in
          let cut, signal_cut = Eio.Promise.create () in
          let timed_out, signal_timed_out = Eio.Promise.create () in
          let payload = String.make 8_000_000 'x' in
          let policy =
            { L.default_policy with max_reply_bytes = String.length payload }
          in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~budget:(fun _ -> Some (Ox.Duration.seconds 2))
                   ~on_budget_exceeded:(fun _ _ -> payload)
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_started ();
                     Eio.Time.sleep env#clock 100.;
                     Ok "late")
                   ~on_peer_error:(function
                     | `Handler_budget_exceeded -> Eio.Promise.resolve signal_cut ()
                     | `Egress_timeout -> Eio.Promise.resolve signal_timed_out ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "flood\n" flow;
              Eio.Promise.await started;
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await cut;
              (* The client never reads, so the write blocks; each advance moves the mock
                 clock past the egress deadline measured from wherever that write began. *)
              let rec settle left =
                if (not (Eio.Promise.is_resolved timed_out)) && left > 0 then (
                  Ox_test.advance env#clock (Ox.Duration.seconds 2);
                  Eio.Fiber.yield ();
                  settle (left - 1))
              in
              settle 5;
              Eio.Promise.await timed_out)))

let budget_reply_absent () =
  (* nipc-i5ni nipc-6i86 nipc-ajmi *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let started, signal_started = Eio.Promise.create () in
          let cut, signal_cut = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~budget:(fun _ -> Some (Ox.Duration.seconds 2))
                   ~handler:(fun _ ->
                     Eio.Promise.resolve signal_started ();
                     Eio.Time.sleep env#clock 100.;
                     Ok "late")
                   ~on_peer_error:(function
                     | `Handler_budget_exceeded -> Eio.Promise.resolve signal_cut ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "silent\n" flow;
              Eio.Promise.await started;
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await cut;
              Alcotest.(check bool)
                "no reply, connection closed" true
                (match Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:64 flow) with
                | _ -> false
                | exception End_of_file -> true))))

let error_reply_decode () =
  (* nipc-c871 nipc-x8ph nipc-ajmi *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let admitted = ref 0 in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~decode:(fun line ->
                     if line = "ping" then Ok line
                     else Error (Printf.sprintf "unparsable: %s" line))
                   ~error_response:(function
                     | `Decode reason ->
                         Some (Printf.sprintf "error malformed-request %s" reason)
                     | _ -> None)
                   ~handler:(fun x ->
                     incr admitted;
                     Ok x)
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "nonsense\n" flow;
              let reader = Eio.Buf_read.of_flow ~max_size:64 flow in
              Alcotest.(check string)
                "malformed request answered with the chosen reply"
                "error malformed-request unparsable: nonsense" (Eio.Buf_read.line reader);
              Alcotest.(check bool)
                "one reply then close" true
                (match Eio.Buf_read.line reader with
                | _ -> false
                | exception End_of_file -> true);
              Alcotest.(check string)
                "a valid request still reaches the handler" "ping"
                (request env sw path "ping\n");
              Alcotest.(check int) "only the valid request was admitted" 1 !admitted)))

let error_reply_oversized () =
  (* nipc-c871 nipc-x8ph *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let admitted = ref 0 in
          let policy = { L.default_policy with max_line_bytes = 4 } in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~error_response:(function
                     | `Ingress_too_large -> Some "error too-large" | _ -> None)
                   ~handler:(fun x ->
                     incr admitted;
                     Ok x)
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "abcdef\n" flow;
              let reader = Eio.Buf_read.of_flow ~max_size:64 flow in
              Alcotest.(check string)
                "overlong request answered with the chosen reply" "error too-large"
                (Eio.Buf_read.line reader);
              Alcotest.(check bool)
                "one reply then close" true
                (match Eio.Buf_read.line reader with
                | _ -> false
                | exception End_of_file -> true);
              Alcotest.(check int) "no handler admitted" 0 !admitted)))

let error_reply_ingress_timeout () =
  (* nipc-c871 nipc-x8ph *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let reported, signal_reported = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~error_response:(function
                     | `Ingress_timeout -> Some "error timeout" | _ -> None)
                   ~on_peer_error:(function
                     | `Ingress_timeout -> Eio.Promise.resolve signal_reported ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "partial" flow;
              Eio.Fiber.yield ();
              Eio.Fiber.yield ();
              Ox_test.advance env#clock (Ox.Duration.seconds 2);
              Eio.Promise.await reported;
              Alcotest.(check string)
                "stalled ingress answered with the chosen reply" "error timeout"
                (Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:64 flow)))))

let error_reply_declined () =
  (* nipc-c871 nipc-ajmi *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let admitted = ref 0 in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~decode:(fun _ -> Error "unparsable")
                   ~error_response:(fun _ -> None)
                   ~handler:(fun x ->
                     incr admitted;
                     Ok x)
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "junk\n" flow;
              Alcotest.(check bool)
                "declined reply closes without writing" true
                (match Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:64 flow) with
                | _ -> false
                | exception End_of_file -> true);
              Alcotest.(check int) "no handler admitted" 0 !admitted)))

let error_reply_byte_bound () =
  (* nipc-c871 nipc-eiy8 *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let seen = ref [] in
          let decoded, signal_decoded = Eio.Promise.create () in
          let rejected, signal_rejected = Eio.Promise.create () in
          let policy = { L.default_policy with max_reply_bytes = 4 } in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~decode:(fun _ -> Error "unparsable")
                   ~error_response:(fun _ -> Some "oversize")
                   ~on_peer_error:(fun e ->
                     seen := e :: !seen;
                     if e = `Decode "unparsable" then
                       Eio.Promise.resolve signal_decoded ();
                     if e = `Egress_too_large then Eio.Promise.resolve signal_rejected ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "junk\n" flow;
              Eio.Promise.await decoded;
              Eio.Promise.await rejected;
              Alcotest.(check bool)
                "the refused reply does not replace the decode cause" true
                (List.mem (`Decode "unparsable") !seen);
              Alcotest.(check bool)
                "oversized error reply writes nothing" true
                (match Eio.Buf_read.line (Eio.Buf_read.of_flow ~max_size:64 flow) with
                | _ -> false
                | exception End_of_file -> true))))

let error_reply_egress_timeout () =
  (* nipc-c871 nipc-eiy8 *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let decoded, signal_decoded = Eio.Promise.create () in
          let timed_out, signal_timed_out = Eio.Promise.create () in
          let payload = String.make 8_000_000 'x' in
          let policy =
            { L.default_policy with max_reply_bytes = String.length payload }
          in
          Eio.Switch.run (fun sw ->
              check_ok
                (start ~policy
                   ~decode:(fun _ -> Error "unparsable")
                   ~error_response:(function `Decode _ -> Some payload | _ -> None)
                   ~on_peer_error:(function
                     | `Decode _ -> Eio.Promise.resolve signal_decoded ()
                     | `Egress_timeout -> Eio.Promise.resolve signal_timed_out ()
                     | _ -> ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "junk\n" flow;
              Eio.Promise.await decoded;
              (* The client never reads, so the error reply write blocks; each advance
                 moves the mock clock past the egress deadline measured from wherever
                 that write began. *)
              let rec settle left =
                if (not (Eio.Promise.is_resolved timed_out)) && left > 0 then (
                  Ox_test.advance env#clock (Ox.Duration.seconds 2);
                  Eio.Fiber.yield ();
                  settle (left - 1))
              in
              settle 5;
              Eio.Promise.await timed_out)))

let error_reply_disconnect () =
  (* nipc-c871 nipc-1v8z *)
  with_dir (fun _ path ->
      Ox_test.run (fun env _ ->
          let seen = ref [] in
          let asked = ref 0 in
          let reported, signal_reported = Eio.Promise.create () in
          Eio.Switch.run (fun sw ->
              check_ok
                (start
                   ~decode:(fun line ->
                     if line = "ok" then Ok line else Error "unparsable")
                   ~error_response:(fun _ ->
                     incr asked;
                     Some "error")
                   ~on_peer_error:(fun e ->
                     seen := e :: !seen;
                     if not (Eio.Promise.is_resolved reported) then
                       Eio.Promise.resolve signal_reported ())
                   env sw path);
              let flow = client env sw path in
              Eio.Flow.copy_string "partial" flow;
              Eio.Flow.close flow;
              Eio.Promise.await reported;
              Alcotest.(check bool)
                "an unfinished request is reported as ingress closed" true
                (List.mem `Ingress_closed !seen);
              Alcotest.(check int) "disconnect never asks for a reply" 0 !asked;
              Alcotest.(check string)
                "listener still serves after the disconnect" "ok"
                (request env sw path "ok\n"))))

let () =
  if Array.length Sys.argv = 3 && Sys.argv.(1) = "--check-lock" then (
    let fd = Unix.openfile (Sys.argv.(2) ^ ".lock") [ Unix.O_RDWR ] 0 in
    let exit_code =
      match Unix.lockf fd Unix.F_TLOCK 0 with
      | () -> 2
      | exception Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) -> 0
    in
    Unix.close fd;
    exit exit_code)

let () =
  Alcotest.run "ox_ipc"
    [
      ( "nipc-tafd nipc-4kuy nipc-vayc nipc-f264 nipc-uatz",
        [ Alcotest.test_case "directory and ownership" `Quick ownership ] );
      ( "nipc-4kuy nipc-vayc nipc-uatz",
        [ Alcotest.test_case "live and replacement" `Quick live_and_replacement ] );
      ( "nipc-skdt nipc-x8ph nipc-eiy8 nipc-ajmi nipc-01bn",
        [ Alcotest.test_case "bounded line and reply" `Quick line_and_policy ] );
      ( "nipc-x8ph nipc-6i86 nipc-eiy8 nipc-1v8z",
        [ Alcotest.test_case "deadlines and interruption" `Quick deadlines ] );
      ( "nipc-1v8z nipc-uatz nipc-01bn",
        [ Alcotest.test_case "disconnect cancels handler" `Quick disconnect ] );
      ( "nipc-skdt nipc-6i86 nipc-01bn",
        [ Alcotest.test_case "admission saturation" `Quick saturated ] );
      ( "nipc-eiy8 nipc-ajmi nipc-01bn",
        [ Alcotest.test_case "bounded single reply" `Quick reply_bound ] );
      ( "nipc-4kuy nipc-vayc nipc-01bn",
        [
          Alcotest.test_case "cross-process lock" `Quick cross_process;
          Alcotest.test_case "external listener" `Quick live_external;
        ] );
      ( "nipc-uatz nipc-01bn",
        [ Alcotest.test_case "shutdown joins active peer" `Quick shutdown_active ] );
      ( "nipc-eiy8 nipc-01bn",
        [ Alcotest.test_case "blocked egress deadline" `Quick egress_timeout ] );
      ( "nipc-6i86 nipc-01bn",
        [
          Alcotest.test_case "None does not impose handler budget" `Quick unbounded_budget;
        ] );
      ( "nipc-c871 nipc-x8ph nipc-eiy8 nipc-ajmi nipc-1v8z",
        [
          Alcotest.test_case "malformed request gets the chosen error reply" `Quick
            error_reply_decode;
          Alcotest.test_case "overlong request gets the chosen error reply" `Quick
            error_reply_oversized;
          Alcotest.test_case "stalled ingress gets the chosen error reply" `Quick
            error_reply_ingress_timeout;
          Alcotest.test_case "no chosen reply closes without writing" `Quick
            error_reply_declined;
          Alcotest.test_case "error reply obeys the reply byte bound" `Quick
            error_reply_byte_bound;
          Alcotest.test_case "stalled reader hits the egress deadline" `Quick
            error_reply_egress_timeout;
          Alcotest.test_case "disconnect never asks for a reply" `Quick
            error_reply_disconnect;
        ] );
      ( "nipc-i5ni nipc-6i86 nipc-eiy8 nipc-ajmi",
        [
          Alcotest.test_case "chosen budget reply reaches the peer" `Quick budget_reply;
          Alcotest.test_case "chosen budget reply obeys the byte bound" `Quick
            budget_reply_byte_bound;
          Alcotest.test_case "chosen budget reply obeys the egress deadline" `Quick
            budget_reply_egress_deadline;
          Alcotest.test_case "absent callback still closes" `Quick budget_reply_absent;
        ] );
    ]
