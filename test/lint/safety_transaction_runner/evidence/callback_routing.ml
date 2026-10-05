(* ^safe-j6t8 ^safe-m5sp: discover roots without guessing opaque callback lifetime. *)
module P = Ox_sql.Pool

let separate ~sw pool =
  Eio.Fiber.fork ~sw (fun () ->
      ignore (P.Raw.query pool "SELECT 1" []));
  P.with_transaction pool (fun tx -> P.Raw.query tx "SELECT 1" [])

let opaque ~dispatch pool =
  P.with_transaction pool (fun _tx ->
      dispatch (fun () -> P.Raw.query pool "SELECT 1" []))

let nested ~dispatch pool =
  P.with_transaction pool (fun _tx ->
      dispatch (fun () ->
          P.with_transaction pool (fun _tx -> P.Raw.query pool "SELECT 1" [])))
