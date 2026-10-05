(* ^safe-j6t8 ^safe-y047: allocation time, not matching time, establishes independence. *)
module P = Ox_sql.Pool

let inside ~caps ~sw pool =
  P.with_transaction pool (fun _tx ->
      match P.create ~caps ~sw (Ox_sql.Sqlite.memory_config ()) with
      | Ok fresh -> P.Raw.query fresh "SELECT 1" []
      | Error e -> Error e)

let before ~caps ~sw pool =
  let created = P.create ~caps ~sw (Ox_sql.Sqlite.memory_config ()) in
  let alias = created in
  P.with_transaction pool (fun _tx ->
      match alias with Ok fresh -> P.Raw.query fresh "SELECT 1" [] | Error e -> Error e)

let originating ~caps ~sw =
  match P.create ~caps ~sw (Ox_sql.Sqlite.memory_config ()) with
  | Ok fresh ->
      let original = fresh in
      P.with_transaction original (fun _tx -> P.Raw.query fresh "SELECT 1" [])
  | Error e -> Error e

let opaque make pool =
  P.with_transaction pool (fun _tx ->
      match make () with
      | Ok fresh -> P.Raw.query fresh "SELECT 1" []
      | Error e -> Error e)
