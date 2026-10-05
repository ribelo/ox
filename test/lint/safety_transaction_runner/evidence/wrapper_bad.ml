(* ^safe-ldtb ^safe-j6t8 ^safe-fr73: transaction roots inside ordinary Eio callbacks. *)
module P = Ox_sql.Pool

let switch pool =
  Eio.Switch.run (fun _sw ->
      P.with_transaction pool (fun _tx ->
          P.Raw.query pool "SELECT 1" []))

let main pool =
  Eio_main.run (fun _env ->
      P.with_transaction pool (fun _tx ->
          P.Raw.query pool "SELECT 1" []))
