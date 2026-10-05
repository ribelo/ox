module Q = Ox_sql
module P = Q.Pool
module M = Q.Migrate

let get = function
  | Ok value -> value
  | Error (`Ox_sql err) -> Alcotest.failf "SQL error: %a" Q.pp_error err
  | Error `Pool_shutdown -> Alcotest.fail "pool closed"
  | Error `Timeout -> Alcotest.fail "SQL timeout"

let migration = function
  | Ok value -> value
  | Error err -> Alcotest.fail (M.error_to_string err)

(* ^inncap-b8ts: only time is needed to open a pool. *)
let with_pool ~(caps : < Ox_caps.Cap.time ; .. >) f =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let pool =
            get
              (P.create ~caps ~sw ~clock:(Eio.Stdenv.mono_clock env) ~max_size:1
                 (Q.Sqlite.memory_config ()))
          in
          Fun.protect
            ~finally:(fun () ->
              (* ^safe-xls8 ^safe-pufa ^nlint-hxar: Shutdown is best effort in fixture cleanup so its typed error does not replace the test body outcome. *)
              let _shutdown_result =
                P.shutdown pool
                  [@@ox.allow
                    "ox-discarded-result: fixture shutdown is best effort so a cleanup \
                     failure does not replace the test body outcome"]
              in
              ())
            (fun () -> f pool (Eio.Stdenv.mono_clock env))))

module T = struct
  module Make = Q.Table.Make (struct
    let name = "items"
  end)

  include Make

  let id = column "id" Q.int
  let name = column "name" Q.text
end

(* ^nsql-4m2q ^nsql-k3zf: consumer's typed declarations and CRUD. *)
let test_typed ~(caps : < Ox_caps.Cap.time ; .. >) () =
  with_pool ~caps (fun pool _clock ->
      let schema =
        Q.Ox_schema.(
          compile (create_table T.table [ column ~primary_key:true T.id; column T.name ]))
      in
      get (P.Typed.run_schema pool schema);
      let insert =
        Q.Insert.(compile (into T.table |> value T.id 1 |> value T.name "Ada"))
      in
      Alcotest.(check int) "inserted" 1 (get (P.Typed.execute_compiled pool insert));
      let select = Q.Select.(compile (from T.table (Q.Projection.one T.name))) in
      Alcotest.(check (list string))
        "typed rows" [ "Ada" ]
        (get (P.Typed.select pool select));
      Alcotest.(check (list string))
        "typed streaming fold" [ "Ada" ]
        (get (P.Typed.fold_select pool select ~init:[] ~f:(fun acc name -> name :: acc)));
      Alcotest.(check int)
        "raw streaming fold" 1
        (get (P.Raw.fold pool "SELECT name FROM items" [] ~init:0 ~f:(fun n _ -> n + 1)));
      let rows = get (P.Raw.query pool "PRAGMA table_info(items)" []) in
      Alcotest.(check bool) "raw pragma" true (List.length rows >= 2))

(* ^nsql-p8na ^nsql-k3zf: rollback before lease reuse, explicit shutdown. *)
let test_rollback ~(caps : < Ox_caps.Cap.time ; .. >) () =
  with_pool ~caps (fun pool _clock ->
      ignore (get (P.Raw.execute pool "CREATE TABLE tx (value TEXT)" []));
      (match
         P.with_transaction pool (fun tx ->
             ignore (get (P.Raw.execute tx "INSERT INTO tx VALUES ('x')" []));
             Error (`Ox_sql (Q.Pool_error "stop")))
       with
      | Error _ -> ()
      | Ok _ -> Alcotest.fail "rollback unexpectedly committed");
      Alcotest.(check (list string))
        "rolled back" []
        (get (P.Raw.query pool "SELECT value FROM tx" [])
        |> List.filter_map (Q.Row.string "value"));
      ignore (get (P.shutdown pool));
      match P.Raw.query pool "SELECT 1" [] with
      | Error `Pool_shutdown -> ()
      | _ -> Alcotest.fail "query succeeded after shutdown")

(* ^nsql-k3zf ^nsql-p8na: timed-out waiter leaves the borrowed handle healthy. *)
let test_timeout ~(caps : < Ox_caps.Cap.time ; .. >) () =
  with_pool ~caps (fun pool _clock ->
      let result =
        P.Raw.with_connection pool (fun _ ->
            match P.Raw.query ~timeout:(Ox.Duration.ms 20) pool "SELECT 1" [] with
            | Error `Timeout -> Ok ()
            | _ -> Alcotest.fail "wait for occupied pool did not time out")
      in
      ignore (get result);
      Alcotest.(check int)
        "handle reused after timeout" 1
        (List.length (get (P.Raw.query pool "SELECT 1" []))))

(* ^nsql-v5td: ordered application, checksum rejection, reversible downgrade. *)
let test_migrations ~(caps : < Ox_caps.Cap.time ; Ox_caps.Cap.fs_read ; .. >) () =
  with_pool ~caps (fun pool clock ->
      let version = M.Version.from_int 1 |> Result.get_ok in
      let up =
        M.Migration.make ~version ~description:"create table"
          ~migration_type:M.Reversible_up ~sql:"CREATE TABLE demo (id INTEGER)" ()
      in
      let down =
        M.Migration.make ~version ~description:"drop table"
          ~migration_type:M.Reversible_down ~sql:"DROP TABLE demo" ()
      in
      let source = M.Source.from_migrations [ down; up ] in
      let report = migration (M.run ~caps ~clock pool source) in
      Alcotest.(check int) "applied" 1 (List.length report.applied);
      Alcotest.(check int)
        "already applied" 1
        (List.length (migration (M.run ~caps ~clock pool source)).already_applied);
      let drifted =
        M.Migration.make ~version ~description:"changed" ~migration_type:M.Reversible_up
          ~sql:"CREATE TABLE demo (name TEXT)" ()
      in
      (match M.run ~caps ~clock pool (M.Source.from_migrations [ drifted ]) with
      | Error (M.Version_mismatch _) -> ()
      | _ -> Alcotest.fail "checksum change was accepted");
      ignore
        (migration (M.undo ~caps pool source ~target:(M.Version.from_int64_unchecked 0L)));
      let broken =
        M.Migration.make ~version ~description:"broken" ~migration_type:M.Simple
          ~sql:"CREATE TABLE bad (" ()
      in
      let broken_source = M.Source.from_migrations [ broken ] in
      (match M.run ~caps ~clock pool broken_source with
      | Error (M.Sql_error _) -> ()
      | _ -> Alcotest.fail "invalid migration unexpectedly succeeded");
      match M.run ~caps ~clock pool broken_source with
      | Error (M.Dirty version2) when M.Version.equal version version2 -> ()
      | _ -> Alcotest.fail "failed migration did not leave a dirty marker")

let case name f = Alcotest.test_case name `Quick f

let () =
  let caps =
    (Ox_test.powerbox ()
      :> < Ox_caps.Cap.time
         ; Ox_caps.Cap.fs_read
         ; Ox_caps.Cap.tmp
         ; Ox_caps.Cap.fs_write >)
  in
  Alcotest.run "ox_sql"
    [
      ( "sqlite ^nsql-7x9b ^nsql-c2jw",
        [
          case "prepared bind scan" Test_sqlite.test_sqlite_memory_prepare_bind_scan;
          case "structured prepare error" Test_sqlite.test_sqlite_structured_prepare_error;
          case "range and constraint" Test_sqlite.test_sqlite_range_and_constraint_errors;
          case "transaction and savepoint"
            Test_sqlite.test_sqlite_transactions_and_savepoints;
          case "commit cleanup"
            Test_sqlite.test_sqlite_transaction_commit_failure_rolls_back;
          case "blob metadata" Test_sqlite.test_sqlite_float_blob_metadata_and_counters;
          case "backup restore" (Test_sqlite.test_sqlite_backup_and_restore ~caps);
          case "extension toggle" Test_sqlite.test_sqlite_load_extension_toggle;
          case "config errors"
            (Test_sqlite.test_sqlite_config_error_and_testing_helpers ~caps);
          case "unexpected step"
            Test_sqlite.test_sqlite_unexpected_step_success_is_typed_error;
        ] );
      ( "DSL transaction ^nsql-4m2q ^nsql-c2jw",
        [
          case "commit" Test_sql_dsl_transaction.test_commit_success_does_not_rollback;
          case "begin error"
            Test_sql_dsl_transaction.test_begin_returned_does_not_rollback;
          case "begin raise" Test_sql_dsl_transaction.test_begin_raised_does_not_rollback;
          case "body error" Test_sql_dsl_transaction.test_body_returned_rolls_back_once;
          case "body raise" Test_sql_dsl_transaction.test_body_raised_rolls_back_once;
          case "commit error"
            Test_sql_dsl_transaction.test_commit_returned_rolls_back_once;
          case "commit raise" Test_sql_dsl_transaction.test_commit_raised_rolls_back_once;
          case "rollback error"
            Test_sql_dsl_transaction.test_body_returned_rollback_returned;
          case "rollback raise"
            Test_sql_dsl_transaction.test_body_raised_rollback_raised_once;
          case "commit rollback raise"
            Test_sql_dsl_transaction.test_commit_raised_rollback_raised_once;
        ] );
      ("SQLite cancellation", Test_sqlite_cancellation.tests);
      ( "Eio pool and migration ^inncap-b8ts",
        [
          case "typed CRUD and pragma" (test_typed ~caps);
          case "transaction rollback" (test_rollback ~caps);
          case "pool timeout and reuse" (test_timeout ~caps);
          case "migration checksum" (test_migrations ~caps);
        ] );
    ]
