(* ^safe-r1xw ^safe-ldtb: commit and rollback at the public runner seam. *)
module P = Ox_sql.Pool
module R = P.Raw

let get = function
  | Ok value -> value
  | Error (`Ox_sql err) -> failwith (Ox_sql.show_error err)
  | Error `Pool_shutdown -> failwith "pool shut down"
  | Error `Timeout -> failwith "pool timed out"

let count pool =
  match get (R.query pool "SELECT COUNT(*) AS n FROM entries" []) with
  | [ row ] -> (
      match Ox_sql.Row.int "n" row with Some n -> n | None -> failwith "missing count")
  | _ -> failwith "expected count row"

let () =
  Eio_main.run (fun env ->
      Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds env#mono_clock 3.) (fun () ->
          Eio.Switch.run (fun sw ->
              let caps = Ox_test.powerbox () in
              let pool =
                get
                  (P.create ~caps ~sw ~clock:env#mono_clock ~max_size:1
                     (Ox_sql.Sqlite.memory_config ()))
              in
              get (R.execute_script pool "CREATE TABLE entries (value INTEGER)");
              let committed =
                get
                  (P.with_transaction pool (fun tx ->
                       R.execute tx "INSERT INTO entries VALUES (1)" []))
              in
              if committed <> 1 || count pool <> 1 then
                failwith "commit did not retain the row";
              let sentinel = `Ox_sql (Ox_sql.Invalid_query "rollback fixture") in
              let rolled_back =
                P.with_transaction pool (fun tx ->
                    let _inserted =
                      get (R.execute tx "INSERT INTO entries VALUES (2)" [])
                    in
                    Error sentinel)
              in
              (match rolled_back with
              | Error actual when actual = sentinel -> ()
              | _ -> failwith "rollback replaced the primary returned error");
              if count pool <> 1 then failwith "returned error did not roll back";
              (match
                 P.with_transaction pool (fun tx ->
                     let _inserted =
                       get (R.execute tx "INSERT INTO entries VALUES (3)" [])
                     in
                     failwith "raised rollback fixture")
               with
              | exception Failure message when message = "raised rollback fixture" -> ()
              | _ -> failwith "rollback replaced the primary defect");
              if count pool <> 1 then failwith "raised defect did not roll back";
              (* The bad runner is bounded by the public deadline: never wait forever
                 for the only connection already held by with_transaction. *)
              let wrong =
                P.with_transaction pool (fun _tx ->
                    R.execute ~timeout:(Ox.Duration.ms 10) pool
                      "INSERT INTO entries VALUES (4)" [])
              in
              (match wrong with
              | Error (`Ox_sql (Ox_sql.Pool_error "transaction timed out")) -> ()
              | _ ->
                  failwith "originating pool did not encounter the bounded lease failure");
              if count pool <> 1 then failwith "timed-out bypass changed the database")))
