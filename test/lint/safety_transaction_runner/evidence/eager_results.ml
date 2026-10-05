(* ^safe-j6t8 ^safe-m5sp: eager scalar values are not captured runner payloads. *)
module P = Ox_sql.Pool
module Shadow = struct
  type int = { runner : P.tx P.runner }
end

type scalar = int
let get = function Ok value -> value | Error _ -> failwith "SQL error"

let clean ~consume pool =
  P.with_transaction pool (fun tx ->
      let computed = get (P.Raw.execute tx "SELECT 1" []) in
      consume ((computed + get (P.Raw.execute tx "SELECT 1" [])) : scalar);
      Ok ())

let direct ~sink pool =
  P.with_transaction pool (fun tx ->
      sink tx;
      Ok ())

let closure ~sink pool =
  P.with_transaction pool (fun tx ->
      sink (fun () -> get (P.Raw.execute tx "SELECT 1" []));
      Ok ())

let tuple ~sink pool =
  P.with_transaction pool (fun tx ->
      sink (tx, 0);
      Ok ())

let record ~sink pool =
  P.with_transaction pool (fun tx ->
      sink { Shadow.runner = tx };
      Ok ())

let produced ~(produce : P.tx P.runner -> int) ~consume pool =
  P.with_transaction pool (fun tx ->
      consume (produce tx);
      Ok ())

let nested_wrong ~consume pool =
  P.with_transaction pool (fun _tx ->
      consume (get (P.Raw.execute pool "SELECT 1" []));
      Ok ())

let result ~sink pool =
  P.with_transaction pool (fun tx ->
      sink (Ok tx);
      Ok ())
