(* ^safe-j6t8 ^safe-tlyw: nested leases and unrelated pure recursion. Named result discards are intentional static routing evidence. *)
module P = Ox_sql.Pool

let run pool =
  P.with_transaction pool (fun outer ->
      let _r = P.with_transaction pool (fun inner -> P.Raw.query inner "SELECT 1" []) in
      let rec length = function [] -> 0 | _ :: rest -> 1 + length rest in
      let _r = length [ 1; 2; 3 ] in
      P.Raw.query outer "SELECT 1" [])
