(* ^safe-j6t8 ^safe-y047: invocation, not closure construction. Named result discards are intentional static routing evidence. *)
module P = Ox_sql.Pool
module R = P.Raw

let cases ~opaque ~schedule pool (other : P.t) =
  P.with_transaction pool (fun tx ->
      let helper _ runner =
        let alias = runner in
        R.query alias "SELECT 1" []
      in
      let _r = helper () pool in
      (* defect multi parameter alias *)
      let _r = helper () tx in
      let _r = opaque other in
      (* undecided possible alias *)
      let saved () = R.query pool "SELECT 1" [] in
      let _r = schedule saved in
      (* undecided opaque closure *)
      let _r = R.with_connection tx (fun _ -> R.query pool "SELECT 1" []) in
      (* defect known callback *)
      let deferred _ runner = R.query runner "SELECT 1" [] in
      let _kept = deferred () in
      let _r = ignore pool in
      let module Local = struct
        let execute _ _ _ = Ok 0
      end in
      let _r = Local.execute pool "SELECT 1" [] in
      Ok saved)
