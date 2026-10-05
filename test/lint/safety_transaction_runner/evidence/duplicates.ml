(* ^safe-j6t8 ^safe-y047: two invocations preserve duplicate physical sites. *)
module P = Ox_sql.Pool

let run pool =
  P.with_transaction pool (fun _tx ->
      let helper runner = P.Raw.query runner "SELECT 1" [] in
      let _first = helper pool in
      helper pool)
