(* ^safe-fr73 ^safe-tlyw: supplied runner and post-callback work are clean. *)
module P = Ox_sql.Pool

let run pool =
  let result =
    P.with_transaction pool (fun tx ->
        let alias = tx in
        P.Raw.execute alias "SELECT 1" [])
  in
  match result with
  | Error error -> Error error
  | Ok _ -> P.Raw.execute pool "SELECT 1" []
