(* ^nstress-kcr6. Libraries: stress_support ox ox_ipc ox_test eio eio_main unix. *)
module L = Ox_ipc.Listener

type mode = Reply | Budget | Partial_drop | Handler_drop
type outcome = Pending | Answered | Dropped

let fail fmt = Printf.ksprintf failwith fmt
let check label condition = if not condition then fail "%s" label
let fd_count () = Array.length (Sys.readdir "/proc/self/fd")
let clients = 200

let with_dir f =
  let dir = Filename.temp_file ~temp_dir:"/tmp" "ox-ipc-storm-" "" in
  Unix.unlink dir;
  Unix.mkdir dir 0o700;
  let path = Filename.concat dir "socket" in
  Fun.protect
    ~finally:(fun () ->
      (* Only our private directory's two known artifacts are removed. *)
      List.iter
        (fun path ->
          try Unix.unlink path with Unix.Unix_error (Unix.ENOENT, _, _) -> ())
        [ path; path ^ ".lock" ];
      Unix.rmdir dir)
    (fun () -> f path)

let mode_name = function
  | Reply | Partial_drop -> "reply"
  | Budget -> "budget"
  | Handler_drop -> "drop"

let round env random path =
  let modes =
    Array.init clients (fun id ->
        (* Guarantee all four cases, then vary the rest from the printed seed. *)
        match if id < 4 then id else Random.State.int random 4 with
        | 0 -> Reply
        | 1 -> Budget
        | 2 -> Partial_drop
        | _ -> Handler_drop)
  in
  let requests =
    Array.mapi (fun id mode -> Printf.sprintf "%d:%s" id (mode_name mode)) modes
  in
  let cuts =
    Array.map
      (fun request -> 1 + Random.State.int random (String.length request - 1))
      requests
  in
  let pauses = Array.init clients (fun _ -> Random.State.float random 0.003) in
  let entered = Array.init clients (fun _ -> Eio.Promise.create ()) in
  let handled = Array.make clients false and finalized = Array.make clients false in
  let outcomes = Array.make clients Pending
  and budget_replies = Array.make clients false in
  let normal_count = ref 0
  and budget_count = ref 0
  and partial_count = ref 0
  and drop_count = ref 0 in
  let active = ref 0 and connected = ref 0 in
  let changed = Eio.Condition.create () in
  let start, release = Eio.Promise.create () in
  let changed_count counter =
    incr counter;
    Eio.Condition.broadcast changed
  in
  let expected mode =
    Array.fold_left (fun count m -> count + if m = mode then 1 else 0) 0 modes
  in
  let decode line =
    match String.split_on_char ':' line with
    | [ id; _ ] -> (
        match int_of_string_opt id with
        | Some id when id >= 0 && id < clients && line = requests.(id) -> Ok id
        | _ -> Error "unknown request")
    | _ -> Error "malformed request"
  in
  let on_peer_error = function
    | `Ingress_closed -> changed_count partial_count
    | `Disconnected -> changed_count drop_count
    | `Handler_budget_exceeded -> changed_count budget_count
    | _ -> fail "listener reported an unexpected peer error"
  in
  let leaked =
    Ox_test.with_census (fun () ->
        Eio.Switch.run (fun sw ->
            let policy =
              {
                L.default_policy with
                peers = clients;
                backlog = clients + 32;
                ingress = Ox.Duration.seconds 2;
                egress = Ox.Duration.seconds 2;
              }
            in
            (match
               L.run ~caps:(Ox_test.powerbox ()) ~sw ~fs:env#fs ~net:env#net
                 ~clock:env#clock ~path ~policy ~decode ~encode:Fun.id
                 ~budget:(fun id ->
                   if modes.(id) = Budget then Some (Ox.Duration.ms 50) else None)
                 ~handler:(fun id ->
                   check "request handler entered twice" (not handled.(id));
                   handled.(id) <- true;
                   incr active;
                   Eio.Promise.resolve (snd entered.(id)) ();
                   Fun.protect
                     ~finally:(fun () ->
                       finalized.(id) <- true;
                       decr active;
                       Eio.Condition.broadcast changed)
                     (fun () ->
                       Eio.Time.sleep env#clock
                         (match modes.(id) with
                         | Reply -> pauses.(id)
                         | Budget | Handler_drop -> 10.
                         | Partial_drop -> fail "partial request reached the handler");
                       incr normal_count;
                       Ok (Printf.sprintf "reply:%d" id)))
                 ~on_budget_exceeded:(fun id _ ->
                   check "budget reply invoked for non-budget request"
                     (modes.(id) = Budget);
                   check "budget reply invoked twice" (not budget_replies.(id));
                   check "budget reply preceded handler finalization" finalized.(id);
                   budget_replies.(id) <- true;
                   Eio.Condition.broadcast changed;
                   Printf.sprintf "budget:%d" id)
                 ~on_peer_error ()
             with
            | Ok () -> ()
            | Error _ -> fail "IPC listener acquisition failed");
            let client id () =
              Eio.Switch.run (fun client_sw ->
                  let flow = Eio.Net.connect ~sw:client_sw env#net (`Unix path) in
                  incr connected;
                  if !connected = clients then Eio.Promise.resolve release ();
                  Eio.Promise.await start;
                  let request = requests.(id) in
                  let cut = cuts.(id) in
                  Eio.Flow.copy_string (String.sub request 0 cut) flow;
                  Eio.Time.sleep env#clock pauses.(id);
                  match modes.(id) with
                  | Partial_drop ->
                      Eio.Flow.close flow;
                      outcomes.(id) <- Dropped
                  | Reply | Budget | Handler_drop ->
                      Eio.Flow.copy_string
                        (String.sub request cut (String.length request - cut) ^ "\n")
                        flow;
                      if modes.(id) = Handler_drop then (
                        Eio.Promise.await (fst entered.(id));
                        Eio.Time.sleep env#clock pauses.(id);
                        Eio.Flow.close flow;
                        outcomes.(id) <- Dropped)
                      else
                        let input = Eio.Buf_read.of_flow ~max_size:4096 flow in
                        let reply = Eio.Buf_read.line input in
                        let expected =
                          Printf.sprintf "%s:%d"
                            (if modes.(id) = Budget then "budget" else "reply")
                            id
                        in
                        if reply <> expected then
                          fail "client %d: expected %S, got %S" id expected reply;
                        (* A reply alone is not enough: the peer must release too. *)
                        (match Eio.Buf_read.line input with
                        | _ -> fail "client %d received more than one reply" id
                        | exception End_of_file -> ());
                        outcomes.(id) <- Answered)
            in
            Eio.Fiber.all (List.init clients client);
            let settled () =
              !partial_count = expected Partial_drop
              && !drop_count = expected Handler_drop
              && !budget_count = expected Budget
              && !normal_count = expected Reply
              && !active = 0
            in
            while not (settled ()) do
              Eio.Condition.await_no_mutex changed
            done;
            Array.iteri
              (fun id mode ->
                check "client outcome was lost"
                  (outcomes.(id)
                  =
                  match mode with
                  | Reply | Budget -> Answered
                  | Partial_drop | Handler_drop -> Dropped);
                check "budget reply was not written and consumed"
                  (budget_replies.(id) = (mode = Budget));
                check "handler was not joined before listener shutdown"
                  (finalized.(id) = (mode <> Partial_drop)))
              modes))
  in
  check "IPC listener switch leaked fibers" (leaked = 0);
  check "IPC listener left its socket behind" (not (Sys.file_exists path));
  (!normal_count, !budget_count, !partial_count + !drop_count)

let () =
  let random = Stress_support.random ~default:60036 () in
  with_dir (fun path ->
      Eio_main.run (fun env ->
          Eio.Time.sleep env#clock 0.001;
          let before = fd_count () in
          let replies = ref 0 and budgets = ref 0 and dropped = ref 0 in
          Eio.Time.with_timeout_exn env#clock 45. (fun () ->
              for _ = 1 to 8 do
                let answered, budget, drops = round env random path in
                replies := !replies + answered;
                budgets := !budgets + budget;
                dropped := !dropped + drops;
                check "IPC storm leaked descriptors" (fd_count () = before)
              done);
          check "connections were not all accounted for"
            (!replies + !budgets + !dropped = 8 * clients);
          Printf.printf
            "ipc_storm: 8 x 200 concurrent clients; %d replies, %d budget replies, %d \
             clean drops; no leaked fibers/fds\n\
             %!"
            !replies !budgets !dropped))
