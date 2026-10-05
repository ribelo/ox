(* ^safe-ldtb ^safe-fr73: every current public runner operation, not name heuristics. *)
module P = Ox_sql.Pool

let run ~select ~returning ~change ~schema pool =
  P.with_transaction pool (fun _tx ->
      let _r = P.Raw.query pool "SELECT 1" [] in
      let _r = P.Raw.fold pool "SELECT 1" [] ~init:() ~f:(fun () _ -> ()) in
      let _r = P.Raw.execute pool "SELECT 1" [] in
      let _r = P.Raw.execute_script pool "SELECT 1" in
      let _r = P.Raw.with_connection pool (fun _ -> Ok ()) in
      let _r = P.Typed.select pool select in
      let _r = P.Typed.returning pool returning in
      let _r = P.Typed.fold_select pool select ~init:() ~f:(fun () _ -> ()) in
      let _r = P.Typed.execute_compiled pool change in
      let _r = P.Typed.run_schema pool schema in
      Ok ())
