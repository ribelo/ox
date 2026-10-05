module Q = Ox_sql
module P = Q.Pool
module M = Q.Migrate
module Clock = Eio_mock.Clock

let get = function
  | Ok value -> value
  | Error (`Ox_sql err) -> Alcotest.failf "SQL error: %a" Q.pp_error err
  | Error `Pool_shutdown -> Alcotest.fail "pool closed"
  | Error `Timeout -> Alcotest.fail "unexpected timeout"

let migration = function
  | Ok value -> value
  | Error err -> Alcotest.fail (M.error_to_string err)

let ns n = Mtime.of_uint64_ns n

let check_pending promise =
  Alcotest.(check bool) "deadline has not fired" true (Eio.Promise.peek promise = None)

let check_timeout = function
  | Error `Timeout -> ()
  | _ -> Alcotest.fail "expected typed SQL timeout"

let with_pool ~caps ?default_timeout f =
  Eio_mock.Backend.run (fun () ->
      let wall = Clock.make () in
      let mono = Clock.Mono.make () in
      Clock.set_time wall 1_000.;
      Eio.Switch.run (fun sw ->
          let clock = (mono :> Eio.Time.Mono.ty Eio.Time.Mono.t) in
          let pool =
            get
              (P.create ~caps ~sw ~clock ?default_timeout ~max_size:1
                 (Q.Sqlite.memory_config ()))
          in
          f sw wall mono pool;
          get (P.shutdown pool);
          match P.Raw.query pool "SELECT 1" [] with
          | Error `Pool_shutdown -> ()
          | _ -> Alcotest.fail "shutdown did not reject new work"))

(* ^safe-p9cw ^safe-8peq ^safe-5a9k: the occupied lease must outlive either
   wall correction; only the monotonic deadline cancels the waiting borrower. *)
let waiter ~caps ~jump ~default () =
  let default_timeout = if default then Some (Ox.Duration.ms 50) else None in
  with_pool ~caps ?default_timeout (fun sw wall mono pool ->
      get
        (P.Raw.execute_script pool
           "CREATE TABLE retained (n INTEGER); INSERT INTO retained VALUES (1)");
      get
        (P.with_transaction ~timeout:(Ox.Duration.seconds 1) pool (fun _ ->
             let result, resolve = Eio.Promise.create () in
             Eio.Fiber.fork ~sw (fun () ->
                 let timeout = if default then None else Some (Ox.Duration.ms 50) in
                 Eio.Promise.resolve resolve (P.Raw.query ?timeout pool "SELECT 1" []));
             Eio.Fiber.yield ();
             check_pending result;
             Clock.set_time wall jump;
             Eio.Fiber.yield ();
             check_pending result;
             Clock.Mono.set_time mono (ns 49_000_000L);
             Eio.Fiber.yield ();
             check_pending result;
             Clock.Mono.set_time mono (ns 50_000_000L);
             check_timeout (Eio.Promise.await result);
             Ok ()));
      Alcotest.(check (float 0.)) "wall correction retained" jump (Eio.Time.now wall);
      Alcotest.(check int)
        "same in-memory lease remains healthy" 1
        (List.length (get (P.Raw.query pool "SELECT n FROM retained" [])));
      get
        (P.Raw.with_connection pool (fun db ->
             Alcotest.(check bool)
               "owner transaction completed" true (Q.Sqlite.autocommit db);
             Ok ())))

(* ^safe-5a9k: a deadline awaits callback cleanup, rolls back and returns the
   same healthy native connection before its typed Timeout becomes observable. *)
let transaction_timeout ~caps ~jump () =
  with_pool ~caps (fun sw wall mono pool ->
      get (P.Raw.execute_script pool "CREATE TABLE rolled_back (n INTEGER)");
      let entered, enter = Eio.Promise.create () in
      let never, _ = Eio.Promise.create () in
      let result, resolve = Eio.Promise.create () in
      let cleaned = ref false in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Promise.resolve resolve
            (P.with_transaction ~timeout:(Ox.Duration.ms 50) pool (fun tx ->
                 Alcotest.(check int)
                   "inserted row" 1
                   (get (P.Raw.execute tx "INSERT INTO rolled_back VALUES (1)" []));
                 Eio.Promise.resolve enter ();
                 Fun.protect
                   ~finally:(fun () -> cleaned := true)
                   (fun () -> Eio.Promise.await never))));
      Eio.Promise.await entered;
      Clock.set_time wall jump;
      Eio.Fiber.yield ();
      check_pending result;
      Clock.Mono.set_time mono (ns 50_000_000L);
      check_timeout (Eio.Promise.await result);
      Alcotest.(check bool) "cleanup completes before timeout return" true !cleaned;
      Alcotest.(check int)
        "transaction rolled back, table retained" 0
        (List.length (get (P.Raw.query pool "SELECT n FROM rolled_back" [])));
      get
        (P.Raw.with_connection pool (fun db ->
             Alcotest.(check bool) "autocommit restored" true (Q.Sqlite.autocommit db);
             Ok ())))

(* ^safe-5a9k: external cancellation is interruption, not Timeout or a SQL
   error; Scope classifies it only after native rollback and lease cleanup. *)
let cancellation ~caps () =
  with_pool ~caps (fun sw _wall _mono pool ->
      get (P.Raw.execute_script pool "CREATE TABLE cancelled (n INTEGER)");
      let entered, enter = Eio.Promise.create () in
      let never, _ = Eio.Promise.create () in
      let result, resolve = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Promise.resolve resolve
            (Ox.Scope.run (fun _ ->
                 Eio.Cancel.sub (fun cc ->
                     P.with_transaction ~timeout:(Ox.Duration.seconds 1) pool (fun tx ->
                         Alcotest.(check int)
                           "inserted row" 1
                           (get (P.Raw.execute tx "INSERT INTO cancelled VALUES (1)" []));
                         Eio.Promise.resolve enter cc;
                         Eio.Promise.await never)))));
      let cc = Eio.Promise.await entered in
      Eio.Cancel.cancel cc Exit;
      (match Eio.Promise.await result with
      | Ox.Exit.Failure (Ox.Cause.Interrupt _) -> ()
      | _ -> Alcotest.fail "cancellation did not retain interruption identity");
      Alcotest.(check int)
        "cancelled transaction rolled back" 0
        (List.length (get (P.Raw.query pool "SELECT n FROM cancelled" [])));
      get
        (P.Raw.with_connection pool (fun db ->
             Alcotest.(check bool)
               "cancelled lease restored" true (Q.Sqlite.autocommit db);
             Ok ())))

module Migration_clock = struct
  type t = { mono : Clock.Mono.t; wall : Clock.t; jump : float; mutable reads : int }
  type time = Mtime.t

  let now t =
    t.reads <- t.reads + 1;
    if t.reads = 2 then (
      Clock.set_time t.wall t.jump;
      Clock.Mono.set_time t.mono (ns 9_000_000_000_037_999_999L));
    Eio.Time.Mono.now t.mono

  let sleep_until t time = Eio.Time.Mono.sleep_until t.mono time
end

(* ^safe-p9cw ^safe-8peq ^safe-5a9k: native Mtime differences precede float
   conversion. At this large origin, converting absolute samples to float
   first would round 37.999999ms up to 38ms, breaking the persisted integer. *)
let duration ~caps ~jump ~run_to ~no_tx () =
  with_pool ~caps (fun _sw wall mono pool ->
      Clock.Mono.set_time mono (ns 9_000_000_000_000_000_000L);
      let state = Migration_clock.{ mono; wall; jump; reads = 0 } in
      let clock = Eio.Resource.T (state, Eio.Time.Pi.clock (module Migration_clock)) in
      let version = M.Version.from_int64_unchecked 1L in
      let up =
        M.Migration.make ~no_tx ~version ~description:"timed" ~migration_type:M.Simple
          ~sql:"CREATE TABLE timed (n INTEGER)" ()
      in
      let source = M.Source.from_migrations [ up ] in
      let caps = (caps :> < Ox_caps.Cap.fs_read >) in
      let report =
        migration
          (if run_to then M.run_to ~caps ~clock pool source ~target:version
           else M.run ~caps ~clock pool source)
      in
      (match report.applied with
      | [ applied ] ->
          Alcotest.(check int) "report numeric milliseconds" 37 applied.elapsed_ms
      | _ -> Alcotest.fail "expected exactly one applied migration");
      Alcotest.(check int) "exactly two native timestamp reads" 2 state.reads;
      Alcotest.(check (float 0.))
        "wall jumped between duration samples" jump (Eio.Time.now wall);
      let rows =
        get
          (P.Raw.query pool
             "SELECT execution_time_ms, typeof(execution_time_ms) AS storage_type, \
              installed_at, typeof(installed_at) AS calendar_type, success FROM \
              __eta_migrations"
             [])
      in
      (match rows with
      | [ row ] ->
          Alcotest.(check (option int))
            "persisted numeric milliseconds" (Some 37)
            (Q.Row.int "execution_time_ms" row);
          Alcotest.(check (option string))
            "integer storage" (Some "integer")
            (Q.Row.string "storage_type" row);
          Alcotest.(check (option int))
            "successful migration" (Some 1) (Q.Row.int "success" row);
          Alcotest.(check (option string))
            "calendar storage remains text" (Some "text")
            (Q.Row.string "calendar_type" row);
          Alcotest.(check bool)
            "installed_at remains a SQL calendar timestamp" true
            (match Q.Row.string "installed_at" row with
            | Some text -> String.length text = 19 && text.[4] = '-' && text.[10] = ' '
            | None -> false)
      | _ -> Alcotest.fail "missing persisted migration row");
      let again = migration (M.run ~caps ~clock pool source) in
      Alcotest.(check int)
        "already-applied migration not retimed" 0 (List.length again.applied);
      Alcotest.(check int) "no additional clock reads" 2 state.reads;
      get
        (P.Raw.with_connection pool (fun db ->
             Alcotest.(check bool)
               "migration restored autocommit" true (Q.Sqlite.autocommit db);
             Ok ())))

let cases ~caps =
  let directions = [ ("forward", 86_401_000.); ("backward", -86_399_000.) ] in
  let per_direction (name, jump) =
    [
      (name ^ " explicit waiter", waiter ~caps ~jump ~default:false);
      (name ^ " default waiter", waiter ~caps ~jump ~default:true);
      (name ^ " transaction deadline", transaction_timeout ~caps ~jump);
      ( name ^ " run transactional duration",
        duration ~caps ~jump ~run_to:false ~no_tx:false );
      ( name ^ " run_to transactional duration",
        duration ~caps ~jump ~run_to:true ~no_tx:false );
      (name ^ " run no_tx duration", duration ~caps ~jump ~run_to:false ~no_tx:true);
      (name ^ " run_to no_tx duration", duration ~caps ~jump ~run_to:true ~no_tx:true);
    ]
  in
  List.concat_map per_direction directions
  @ [ ("external cancellation", cancellation ~caps) ]

let tests ~caps =
  List.map (fun (name, f) -> Alcotest.test_case name `Quick f) (cases ~caps)

let verify ~caps () = List.iter (fun (_, f) -> f ()) (cases ~caps)
