(* ^safe-eeso ^safe-doj9: compiled public fixture behavior. *)
let () =
  (* A demonstrated runtime defect, not a promise about all comparison fast paths. *)
  let outcome =
    try
      ignore (Function_comparison_fixtures.Bad.ordering (fun x -> x + 1) (fun x -> x + 2));
      false
    with Invalid_argument _ -> true
  in
  if not outcome then
    failwith "distinct function ordering should demonstrate Invalid_argument";
  let original = { Function_comparison_fixtures.Good.id = 7; run = (fun x -> x + 1) } in
  let replacement = { original with run = (fun x -> x + 2) } in
  if not (Function_comparison_fixtures.Good.same_action original replacement) then
    failwith "domain identity should not compare closure implementation"
