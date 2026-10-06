(* ^safe-ldtb ^safe-r1xw: intentional originating-pool defect, declared fixture only. *)
let witness ~caps ~wrong () =
  let get = function Ok x -> x | Error _ -> failwith "transaction witness failed" in
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let pool =
            get
              (Ox_sql.Pool.create ~caps ~sw ~max_size:1 (Ox_sql.Sqlite.memory_config ()))
          in
          get (Ox_sql.Pool.Raw.execute_script pool "CREATE TABLE entries (value INTEGER)");
          let committed =
            get
              (Ox_sql.Pool.with_transaction pool (fun tx ->
                   Ox_sql.Pool.Raw.execute tx "INSERT INTO entries VALUES (1)" []))
          in
          if committed <> 1 then failwith "transaction did not commit";
          let sentinel = `Ox_sql (Ox_sql.Invalid_query "rollback witness") in
          let result =
            Ox_sql.Pool.with_transaction pool (fun tx ->
                let insert =
                  if wrong then
                    Ox_sql.Pool.Raw.execute pool "INSERT INTO entries VALUES (1)" []
                  else Ox_sql.Pool.Raw.execute tx "INSERT INTO entries VALUES (1)" []
                in
                ignore (get insert);
                Error sentinel)
          in
          (match result with
          | Error actual when actual = sentinel -> ()
          | _ -> failwith "primary error replaced");
          match
            get (Ox_sql.Pool.Raw.query pool "SELECT COUNT(*) AS n FROM entries" [])
          with
          | [ row ] when Ox_sql.Row.int "n" row = Some 1 -> ()
          | _ -> failwith "transaction did not roll back"))

let () =
  match Array.to_list Sys.argv with
  | [ _; "--wrong-runner" ] -> witness ~caps:(Ox_test.powerbox ()) ~wrong:true ()
  | [ _; "--witness" ] -> witness ~caps:(Ox_test.powerbox ()) ~wrong:false ()
  | _ -> failwith "usage: transaction_witness --wrong-runner|--witness"
