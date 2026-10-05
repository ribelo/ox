(* ^safe-pufa: installed policy contract. *)
let run () =
  ignore
    (Error "optional" : (unit, string) result)
  [@ox.allow "ox-discarded-result: optional cleanup"];
  ignore (Error "required" : (unit, string) result)
