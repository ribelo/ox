(* nmodes-6pqn: a concrete schedule and failure cross into an Eio domain.
   Cause is explicitly portable; Eio.Domain_manager.run does not require a
   portable callback, and Schedule may contain unrestricted user closures. *)
let in_other_domain domain_mgr
    (schedule : (unit, int) Eta.Schedule.t)
    (cause : string Eta.Cause.t @ portable) =
  Eio.Domain_manager.run domain_mgr (fun () ->
      let decision, _ = Eta.Schedule.step ~now_ms:0 ~input:()
          (Eta.Schedule.start schedule) in
      let attempts = match decision with
        | Eta.Schedule.Continue meta | Eta.Schedule.Done meta -> meta.attempt in
      let cause_is_failure = match cause with Eta.Cause.Fail "sent" -> true | _ -> false in
      attempts, cause_is_failure)

let () =
  Eio_main.run (fun env ->
      let schedule = Eta.Schedule.recurs 1 in
      let cause = Eta.Cause.Fail "sent" in
      match in_other_domain env#domain_mgr schedule cause with
      | attempt, true when attempt >= 0 -> ()
      | _ -> failwith "portable schedule/cause domain transfer failed")
