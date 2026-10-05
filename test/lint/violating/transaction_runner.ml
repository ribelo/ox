(* ^safe-fr73 ^safe-ldtb: captured origin escapes the transaction lease. *)
module P = Ox_sql.Pool

let run pool =
  let original = pool in
  P.with_transaction pool (fun _tx -> P.Raw.execute original "SELECT 1" [])
