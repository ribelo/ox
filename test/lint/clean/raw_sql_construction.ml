(* ^safe-p1m1: generated text and separately bound values remain ordinary SQL. *)
module P = Ox_sql.Pool

let bound runner input =
  P.Raw.execute runner "INSERT INTO users(name) VALUES (?)" [ Ox_sql.Value.string input ]

let generated runner compiled =
  P.Raw.execute_script runner (Ox_sql.Compiled.schema_sql compiled)
