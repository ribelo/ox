(* ^safe-ldtb ^safe-fr73: originating pool bypasses the callback runner. *)
let wrong pool =
  Ox_sql.Pool.with_transaction pool (fun _tx ->
      Ox_sql.Pool.Raw.execute pool "INSERT INTO entries VALUES (1)" [])
