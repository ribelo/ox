(* ^safe-t37w: one physical helper runner visited under two originating pools. *)
module P = Ox_sql.Pool

let run first second =
  let query runner = P.Raw.query runner "SELECT 1" [] in
  let _first = P.with_transaction first (fun _tx -> query first) in
  P.with_transaction second (fun _tx -> query second)
