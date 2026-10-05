(* ^safe-pcom ^safe-28t6: exercise the actual stored callback and failed validation. *)
let () =
  let calls = ref 0 in
  stored_ref (fun () ->
      incr calls;
      raise Exit);
  if !calls <> 1 then failwith "stored_ref must evaluate the failing callback once";
  let rejected =
    try
      stored_ref (fun () -> incr calls);
      false
    with Assert_failure _ -> true
  in
  if not rejected then failwith "stored_ref must reject a callback that does not raise";
  if !calls <> 2 then failwith "stored_ref must evaluate the returning callback once"
