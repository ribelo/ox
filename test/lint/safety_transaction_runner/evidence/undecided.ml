(* ^safe-y047: another parameter may alias the originating pool. *)
module P = Ox_sql.Pool

let run pool (other : P.t) =
  P.with_transaction pool (fun _tx -> P.Raw.query other "SELECT 1" [])
