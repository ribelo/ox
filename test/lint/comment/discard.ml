(* ^nlint-emql: nolint comments must not suppress a typed finding. *)
let comment () =
  (* nolint: ox-discarded-result -- this is not an exemption *)
  ignore (Ok () : (unit, string) result)
