(* ^safe-p1m1: generated text and separately bound values remain ordinary SQL. *)
module P = Ox_sql.Pool

let bound runner input =
  P.Raw.execute runner "INSERT INTO users(name) VALUES (?)" [ Ox_sql.Value.string input ]

let generated runner compiled =
  P.Raw.execute_script runner (Ox_sql.Compiled.schema_sql compiled)

(* ^safe-p1m1: genuine identity survives aliases and a local helper. *)
let _identifier runner input =
  let quote = Ox_sql__Dsl.quote_ident in
  let name input = quote input in
  let table = name input in
  P.Raw.execute runner ("CREATE TABLE " ^ table ^ " (id INTEGER)") []

let _formatted runner input =
  let table = Ox_sql__Dsl.quote_ident input in
  P.Raw.execute runner (Printf.sprintf "CREATE TABLE %s (id INTEGER)" table) []

let _joined runner input =
  let table = Ox_sql__Dsl.quote_ident input in
  P.Raw.execute runner (String.concat " " [ "CREATE TABLE"; table; "(id INTEGER)" ]) []

let _buffered runner input =
  let table = Ox_sql__Dsl.quote_ident input in
  let buffer = Buffer.create 64 in
  Buffer.add_string buffer "CREATE TABLE ";
  Buffer.add_string buffer table;
  Buffer.add_string buffer " (id INTEGER)";
  P.Raw.execute runner (Buffer.contents buffer) []
