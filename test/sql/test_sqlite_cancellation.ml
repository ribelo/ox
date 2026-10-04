module S = Ox_sql.Sqlite
module C = S.Cancellation
module T = Ox_sql_dsl
module B = Ox_blocking

(* Private native synchronization only: these fixtures expose neither a production
   query-notification API nor a timing heuristic. *)
external progress_arm : unit -> unit = "ox_sqlite_test_progress_arm"
external progress_wait : unit -> unit = "ox_sqlite_test_progress_wait"
external progress_release : unit -> unit = "ox_sqlite_test_progress_release"
external close_arm : unit -> unit = "ox_sqlite_test_close_arm"
external close_wait : unit -> unit = "ox_sqlite_test_close_wait"
external close_release : unit -> unit = "ox_sqlite_test_close_release"

let rc =
  Alcotest.testable (fun fmt rc -> Format.pp_print_string fmt (S.rc_name rc)) S.rc_equal

let check_rc label expected actual = Alcotest.check rc label expected actual
let get = function Ok value -> value | Error err -> Alcotest.failf "%a" S.pp_error err

let worker = function
  | Ok value -> value
  | Error `Shutting_down -> Alcotest.fail "worker pool closed"

let with_db f =
  let db = S.open_memory () in
  Fun.protect ~finally:(fun () -> ignore (S.close db)) (fun () -> f db)

let with_workers f =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 10. (fun () ->
          Eio.Switch.run (fun sw ->
              let pool =
                B.Pool.create ~sw
                  { max_threads = 2; max_queued = 2; shutdown_policy = Drain }
              in
              Fun.protect
                ~finally:(fun () -> Eio.Cancel.protect (fun () -> B.Pool.shutdown pool))
                (fun () -> f sw pool))))

let setup db = get (S.exec_script_result db "CREATE TABLE entries (value INTEGER)")

let row_count db =
  let stmt = get (S.prepare_owned_result db "SELECT COUNT(*) FROM entries") in
  Fun.protect
    ~finally:(fun () -> ignore (S.finalize stmt))
    (fun () ->
      check_rc "count row" S.row (S.step stmt);
      S.column_int stmt 0)

let check_interrupt = function
  | Error err -> check_rc "typed interrupt" S.interrupt_ err.S.code
  | Ok _ -> Alcotest.fail "cancelled native entry succeeded"

let protected token (resource @ local) (f @ local) =
  C.with_handler token (fun () -> f resource) [@nontail]

let sql_result = function Ok x -> Ok x | Error err -> Error (`Sqlite err)

let insert (db @ local) =
  sql_result (S.exec_result db "INSERT INTO entries VALUES (1)")

let begin_ (db @ local) = sql_result (S.begin_transaction_result db)
let commit (db @ local) = sql_result (S.commit_result db)
let rollback (db @ local) = sql_result (S.rollback_result db)

(* ^nsql-hten ^nsql-n11a ^nsql-kbdp: tiny work cannot reach a progress callback. *)
let native_entry () =
  with_db (fun db ->
      setup db;
      let stmt = get (S.prepare_owned_result db "INSERT INTO entries VALUES (1)") in
      let read = get (S.prepare_owned_result db "SELECT 1") in
      Fun.protect
        ~finally:(fun () ->
          ignore (S.finalize stmt);
          ignore (S.finalize read))
        (fun () ->
          let token = C.create db in
          C.request token;
          C.request token;
          protected token db (fun db ->
              check_interrupt (S.exec_script_result db "INSERT INTO entries VALUES (2)");
              check_interrupt (S.exec_result db "INSERT INTO entries VALUES (3)");
              check_interrupt (S.prepare_result db "SELECT 1") [@nontail];
              check_rc "pre-requested prepared INSERT" S.interrupt_ (S.step stmt);
              check_rc "pre-requested tiny read" S.interrupt_ (S.step read));
          Alcotest.(check int) "no native mutations" 0 (S.total_changes db);
          Alcotest.(check int) "no inserted row" 0 (row_count db);
          protected token db (fun db ->
              check_interrupt (S.exec_script_result db "INSERT INTO entries VALUES (4)"));
          Alcotest.(check int) "token never resets" 0 (row_count db)))

(* ^nsql-bgvv ^nsql-iypi ^nsql-n11a ^nsql-kbdp: exec and prepared COMMIT gates. *)
let commit_entry () =
  List.iter
    (fun prepared ->
      with_db (fun db ->
          setup db;
          get (S.begin_transaction_result db);
          get (S.exec_result db "INSERT INTO entries VALUES (1)");
          let stmt =
            if prepared then Some (get (S.prepare_owned_result db "COMMIT")) else None
          in
          let token = C.create db in
          C.request token;
          protected token db (fun db ->
              match stmt with
              | None -> check_interrupt (S.commit_result db)
              | Some stmt -> check_rc "prepared COMMIT blocked" S.interrupt_ (S.step stmt));
          Option.iter (fun stmt -> check_rc "COMMIT finalize" S.ok (S.finalize stmt)) stmt;
          Alcotest.(check bool) "not committed" false (S.autocommit db);
          Alcotest.(check int) "uncommitted row remains for cleanup" 1 (row_count db);
          get (S.rollback_result db);
          Alcotest.(check bool) "rollback restored autocommit" true (S.autocommit db);
          Alcotest.(check int) "rolled-back row absent" 0 (row_count db)))
    [ false; true ]

(* ^nsql-iypi ^nsql-7mzz ^nsql-kbdp ^nsql-p8na: each callback owns its scope;
   the pure transaction combinator runs rollback outside the sticky handler. *)
let body_failure_rollback () =
  with_db (fun db ->
      setup db;
      let token = C.create db in
      let outcome =
        T.transaction
          ~begin_:(fun db -> protected token db (fun db -> begin_ db))
          ~commit:(fun db -> protected token db (fun db -> commit db))
          ~rollback db
          (fun db ->
            protected token db (fun db ->
                get (S.exec_result db "INSERT INTO entries VALUES (1)");
                C.request token;
                Alcotest.(check bool) "not SQLite auto-rollback" false (S.autocommit db);
                Error `Body_rejected))
      in
      (match outcome with
      | T.Failed
          {
            phase = Body;
            primary = Returned `Body_rejected;
            rollback = Rollback_succeeded;
          } ->
          ()
      | _ -> Alcotest.fail "primary body failure or successful rollback lost");
      Alcotest.(check bool) "autocommit restored" true (S.autocommit db);
      Alcotest.(check int) "no uncommitted row" 0 (row_count db);
      C.with_handler (C.create db) (fun () ->
          get (S.exec_result db "INSERT INTO entries VALUES (2)"));
      Alcotest.(check int) "fresh-token work" 1 (row_count db))

(* ^nsql-bgvv ^nsql-iypi ^nsql-9ykc ^nsql-kbdp: cancellation in commit callback. *)
let commit_failure_rollback () =
  with_db (fun db ->
      setup db;
      let token = C.create db in
      let outcome =
        T.transaction
          ~begin_:(fun db -> protected token db (fun db -> begin_ db))
          ~commit:(fun db ->
            C.request token;
            protected token db (fun db -> commit db))
          ~rollback db
          (fun db -> protected token db (fun db -> insert db))
      in
      (match outcome with
      | T.Failed
          {
            phase = Commit;
            primary = Returned (`Sqlite err);
            rollback = Rollback_succeeded;
          } ->
          check_rc "commit primary interrupt" S.interrupt_ err.code
      | _ -> Alcotest.fail "commit failure or rollback lost");
      Alcotest.(check bool) "autocommit restored" true (S.autocommit db);
      Alcotest.(check int) "commit did not publish row" 0 (row_count db))

exception Body_defect
exception Rollback_defect

let[@inline never] raise_body_defect () = raise Body_defect

(* ^nsql-9ykc ^nsql-iypi ^nsql-7mzz: generic failures and owner-side discard.
   These fixtures dispose failed-cleanup handles; Exergy owns production policy. *)
let primary_and_rollback_failures () =
  List.iter
    (fun commit_fails ->
      with_db (fun db ->
          setup db;
          let token = C.create db in
          let outcome =
            T.transaction
              ~begin_:(fun db -> protected token db begin_)
              ~commit:(fun db -> protected token db (fun _ -> Error `Commit_rejected))
              ~rollback:(fun _ -> Error `Rollback_rejected)
              db
              (fun db ->
                protected token db (fun db ->
                    get (S.exec_result db "INSERT INTO entries VALUES (1)");
                    if commit_fails then Ok ()
                    else (
                      C.request token;
                      Error `Body_rejected)))
          in
          (match outcome with
          | T.Failed
              {
                phase;
                primary = Returned primary;
                rollback = Rollback_failed (Returned `Rollback_rejected);
              } ->
              Alcotest.(check bool)
                "correct primary and phase" true
                (if commit_fails then phase = T.Commit && primary = `Commit_rejected
                 else phase = T.Body && primary = `Body_rejected)
          | _ -> Alcotest.fail "primary plus rollback failure lost");
          Alcotest.(check bool) "failed cleanup is not restored" false (S.autocommit db);
          check_rc "owner discards failed cleanup connection" S.ok (S.close db);
          Alcotest.(check bool)
            "failed cleanup connection not leased again" true (S.is_closed db)))
    [ false; true ]

(* ^nsql-9ykc ^nsql-iypi ^nsql-7mzz ^nsql-p8na: original raised-body trace,
   both successful native rollback and raised rollback failure are preserved. *)
let raised_body_rollback () =
  let previous = Printexc.backtrace_status () in
  Printexc.record_backtrace true;
  Fun.protect
    ~finally:(fun () -> Printexc.record_backtrace previous)
    (fun () ->
      List.iter
        (fun rollback_raises ->
          with_db (fun db ->
              setup db;
              let token = C.create db in
              let original = ref "" in
              let outcome =
                T.transaction
                  ~begin_:(fun db -> protected token db begin_)
                  ~commit:(fun db -> protected token db commit)
                  ~rollback:(fun db ->
                    if rollback_raises then raise Rollback_defect else rollback db)
                  db
                  (fun db ->
                    protected token db (fun db ->
                        get (S.exec_result db "INSERT INTO entries VALUES (1)");
                        C.request token;
                        try raise_body_defect ()
                        with exn ->
                          let bt = Printexc.get_raw_backtrace () in
                          original := Printexc.raw_backtrace_to_string bt;
                          Printexc.raise_with_backtrace exn bt))
              in
              (match outcome with
              | T.Failed
                  { phase = Body; primary = Raised (Body_defect, bt); rollback = cleanup }
                -> (
                  Alcotest.(check bool)
                    "body backtrace captured" true
                    (String.length !original > 0);
                  Alcotest.(check bool)
                    "original body frames retained" true
                    (String.starts_with ~prefix:!original
                       (Printexc.raw_backtrace_to_string bt));
                  match cleanup with
                  | T.Rollback_succeeded when not rollback_raises -> ()
                  | T.Rollback_failed (Raised (Rollback_defect, rollback_bt))
                    when rollback_raises ->
                      Alcotest.(check bool)
                        "rollback backtrace retained" true
                        (Printexc.raw_backtrace_length rollback_bt > 0)
                  | _ -> Alcotest.fail "raised body's rollback diagnosis lost")
              | _ -> Alcotest.fail "raised primary diagnosis lost");
              if rollback_raises then (
                Alcotest.(check bool)
                  "raised rollback did not restore autocommit" false (S.autocommit db);
                check_rc "owner discards raised rollback connection" S.ok (S.close db);
                Alcotest.(check bool) "discarded handle is closed" true (S.is_closed db))
              else (
                Alcotest.(check bool) "raised handler restored" true (S.autocommit db);
                Alcotest.(check int) "raised body row absent" 0 (row_count db);
                C.with_handler (C.create db) (fun () ->
                    get (S.exec_result db "INSERT INTO entries VALUES (2)"));
                Alcotest.(check int) "fresh work after raised body" 1 (row_count db))))
        [ false; true ])

(* ^nsql-7mzz ^nsql-hten: return, typed failure and exception all remove handlers. *)
let restoration () =
  with_db (fun db ->
      setup db;
      let token = C.create db in
      protected token db (fun db ->
          get (S.exec_result db "INSERT INTO entries VALUES (1)"));
      C.request token;
      protected token db (fun db ->
          (check_interrupt (S.prepare_result db "SELECT 1") [@nontail]));
      (try protected token db (fun db -> raise Body_defect) with Body_defect -> ());
      get (S.exec_script_result db "INSERT INTO entries VALUES (2)");
      C.with_handler (C.create db) (fun () ->
          get (S.exec_result db "INSERT INTO entries VALUES (3)"));
      Alcotest.(check int) "connection is not poisoned" 3 (row_count db);
      protected token db (fun db ->
          check_interrupt (S.exec_script_result db "INSERT INTO entries VALUES (4)")))

let long_query =
  "WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<1000000) SELECT \
   sum(x) FROM n"

(* ^nsql-zckh ^nsql-l98b ^nsql-kbdp ^nsql-7mzz: notification is inside the VM. *)
let active_interrupt () =
  with_db (fun db ->
      setup db;
      let stmt = get (S.prepare_owned_result db long_query) in
      Fun.protect
        ~finally:(fun () -> ignore (S.finalize stmt))
        (fun () ->
          with_workers (fun sw pool ->
              let token = C.create db in
              let outcome, resolve = Eio.Promise.create () in
              progress_arm ();
              Fun.protect ~finally:progress_release (fun () ->
                  Eio.Fiber.fork ~sw (fun () ->
                      Eio.Promise.resolve resolve
                        (worker
                           (B.run ~pool (fun () ->
                                protected token db (fun db -> S.step stmt)))));
                  worker (B.run ~pool progress_wait);
                  C.request token;
                  C.request token;
                  progress_release ();
                  check_rc "active VM interrupted" S.interrupt_
                    (Eio.Promise.await outcome);
                  protected token db (fun db ->
                      check_interrupt
                        (S.exec_script_result db "INSERT INTO entries VALUES (1)"));
                  C.with_handler (C.create db) (fun () ->
                      get (S.exec_script_result db "INSERT INTO entries VALUES (2)"));
                  Alcotest.(check int)
                    "fresh operation after active interruption" 1 (row_count db)))))

(* ^nsql-tv6i ^nsql-kbdp: request arrives after native close but before state
   publication. A live statement also keeps SQLite's zombie handle until cleanup. *)
let request_close_cleanup () =
  with_workers (fun sw pool ->
      for _ = 1 to 8 do
        with_db (fun db ->
            let stmt = get (S.prepare_owned_result db "SELECT 1") in
            let token = C.create db in
            let closed, resolve = Eio.Promise.create () in
            close_arm ();
            Fun.protect ~finally:close_release (fun () ->
                Eio.Fiber.fork ~sw (fun () ->
                    Eio.Promise.resolve resolve
                      (worker (B.run ~pool (fun () -> S.close db))));
                worker (B.run ~pool close_wait);
                C.request token;
                check_rc "racing close" S.ok (Eio.Promise.await closed));
            let (), finalize_rc =
              Eio.Fiber.pair
                (fun () ->
                  worker
                    (B.run ~pool (fun () ->
                         C.request token;
                         C.request token)))
                (fun () -> worker (B.run ~pool (fun () -> S.finalize stmt)))
            in
            check_rc "zombie statement cleanup" S.ok finalize_rc;
            Gc.full_major ();
            C.request token;
            protected token db (fun db ->
                check_rc "closed entry is misuse" S.misuse (S.step stmt));
            check_rc "idempotent close" S.ok (S.close db))
      done)

(* ^nsql-kbdp ^nsql-tv6i ^nsql-zckh ^nsql-l98b: cancelling a caller does not
   settle native work. Drain/on_settled are the public physical ownership seam. *)
let blocking_caller_cancellation () =
  with_db (fun db ->
      setup db;
      let stmt = get (S.prepare_owned_result db long_query) in
      with_workers (fun sw pool ->
          let token = C.create db in
          let physical = Atomic.make false in
          let leased = ref true in
          let settled = ref 0 in
          let cancels = ref 0 in
          let caller_done, caller_resolve = Eio.Promise.create () in
          let context, context_resolve = Eio.Promise.create () in
          progress_arm ();
          Fun.protect ~finally:progress_release (fun () ->
              Eio.Fiber.fork ~sw (fun () ->
                  try
                    Eio.Cancel.sub (fun ctx ->
                        Eio.Promise.resolve context_resolve ctx;
                        ((* ^nlint-hxar: The caller is deliberately cancelled; the existing on_settled callback checks the eventual native reply and physical completion. *)
let _native_call_result =
                          (B.run ~pool
                             ~on_cancel:(fun () ->
                               incr cancels;
                               C.request token)
                             ~on_settled:(fun result ->
                               Alcotest.(check bool)
                                 "callback physically finished" true (Atomic.get physical);
                               (match result with
                               | Ok code -> check_rc "settled interrupt" S.interrupt_ code
                               | Error exn ->
                                   Alcotest.failf "native defect: %s"
                                     (Printexc.to_string exn));
                               ignore (S.finalize stmt);
                               check_rc "close only on settlement" S.ok (S.close db);
                               leased := false;
                               incr settled)
                             (fun () ->
                               let code = protected token db (fun db -> S.step stmt) in
                               Atomic.set physical true;
                               code)) in ()));
                    Alcotest.fail "caller cancellation did not propagate"
                  with Eio.Cancel.Cancelled _ -> Eio.Promise.resolve caller_resolve ());
              worker (B.run ~pool progress_wait);
              Eio.Cancel.cancel (Eio.Promise.await context) Body_defect;
              Eio.Promise.await caller_done;
              Alcotest.(check int) "one cancellation request" 1 !cancels;
              Alcotest.(check bool)
                "native callback still paused" false (Atomic.get physical);
              Alcotest.(check bool) "connection still leased" true !leased;
              Alcotest.(check bool) "handle not closed" false (S.is_closed db);
              Alcotest.(check int) "settlement not yet run" 0 !settled;
              Alcotest.(check int)
                "physical worker still active" 1 (B.Pool.stats pool).active;
              let drain_returned = ref false in
              let drained, drained_resolve = Eio.Promise.create () in
              let draining, draining_resolve = Eio.Promise.create () in
              Eio.Fiber.fork ~sw (fun () ->
                  Eio.Promise.resolve draining_resolve ();
                  B.Pool.shutdown pool;
                  drain_returned := true;
                  Eio.Promise.resolve drained_resolve ());
              Eio.Promise.await draining;
              (match
                 B.try_run ~pool (fun () -> Alcotest.fail "sealed pool reused callback")
               with
              | B.Not_run B.Shutting_down -> ()
              | _ -> Alcotest.fail "Drain did not seal admission");
              Alcotest.(check bool)
                "Drain retains lease until progress released" true !leased;
              Alcotest.(check bool) "Drain has not returned" false !drain_returned;
              progress_release ();
              Eio.Promise.await drained;
              Alcotest.(check int) "one physical settlement" 1 !settled;
              Alcotest.(check bool) "lease released after settlement" false !leased;
              Alcotest.(check bool)
                "closed after physical settlement" true (S.is_closed db);
              B.Pool.shutdown pool)))

let tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case "native entry ^nsql-hten ^nsql-n11a ^nsql-kbdp" native_entry;
    case "COMMIT entry ^nsql-bgvv ^nsql-iypi ^nsql-n11a ^nsql-kbdp" commit_entry;
    case "body cancellation rollback ^nsql-iypi ^nsql-7mzz ^nsql-kbdp ^nsql-p8na"
      body_failure_rollback;
    case "commit cancellation rollback ^nsql-bgvv ^nsql-iypi ^nsql-9ykc ^nsql-kbdp"
      commit_failure_rollback;
    case "primary/rollback diagnoses ^nsql-9ykc ^nsql-iypi ^nsql-7mzz"
      primary_and_rollback_failures;
    case "raised body rollback ^nsql-9ykc ^nsql-iypi ^nsql-7mzz ^nsql-p8na"
      raised_body_rollback;
    case "handler restoration ^nsql-7mzz ^nsql-hten" restoration;
    case "active progress ^nsql-zckh ^nsql-l98b ^nsql-kbdp ^nsql-7mzz" active_interrupt;
    case "request/close/cleanup ^nsql-tv6i ^nsql-kbdp" request_close_cleanup;
    case "cancelled caller Drain ^nsql-kbdp ^nsql-tv6i ^nsql-zckh ^nsql-l98b"
      blocking_caller_cancellation;
  ]
