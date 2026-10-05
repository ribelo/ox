(* ^safe-ldtb ^safe-j6t8 ^safe-tlyw: finite positive, clean and undecided cases. Named result discards are intentional static routing evidence. *)
module P = Ox_sql.Pool
module R = P.Raw

let cases ~caps ~sw ~opaque pool other change =
  let _r =
    P.with_transaction pool (fun tx ->
        let alias = pool in
        let raw = R.execute in
        let _r = raw alias "SELECT 1" [] in
        (* defect alias *)
        let _r = P.Typed.execute_compiled pool change in
        (* defect typed *)
        let runner = tx in
        let _r = R.query runner "SELECT 1" [] in
        let helper runner = R.execute runner "SELECT 1" [] in
        let _r = helper pool in
        (* defect local helper *)
        let _r = helper tx in
        let stored () = R.execute pool "SELECT 1" [] in
        let _kept = stored in
        let _r = String.length "pure" in
        let _r = opaque pool in
        (* undecided opaque *)
        let _r = R.query other "SELECT 1" [] in
        (* undecided arbitrary pool *)
        Ok stored)
  in
  let _r = R.query pool "SELECT 1" [] in
  let _r = P.with_transaction pool (function tx -> R.query tx "SELECT 1" []) in
  let _r =
    P.with_transaction pool (fun _tx ->
        let pool = other in
        R.execute pool "SELECT 1" [])
  in
  (* undecided shadow *)
  match P.create ~caps ~sw (Ox_sql.Sqlite.memory_config ()) with
  | Error _ -> ()
  | Ok first -> (
      match P.create ~caps ~sw (Ox_sql.Sqlite.memory_config ()) with
      | Error _ -> ()
      | Ok second ->
          let _r =
            P.with_transaction first (fun tx ->
                let _r = R.query second "SELECT 1" [] in
                R.query tx "SELECT 1" [])
          in
          ())
