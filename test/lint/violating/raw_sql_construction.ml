(* ^safe-8pmk ^safe-iq5u: consumer data is concatenated, not parameter-bound. *)
module P = Ox_sql.Pool
let lookup runner input =
  let sql = "SELECT * FROM users WHERE name = '" ^ input ^ "'" in
  P.Raw.query runner sql []
