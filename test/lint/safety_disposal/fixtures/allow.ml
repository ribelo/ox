(* ^safe-xls8 ^safe-pufa: one checked expression policy decision. *)
let cleanup () =
  ignore
    (Error "cleanup" : (unit, string) result)
  [@ox.allow "ox-discarded-result: keep the primary outcome after optional cleanup"]

let binding () =
  let _optional =
    (Error "optional" : (unit, string) result)
      [@@ox.allow
        "ox-discarded-result: optional work must not replace the primary outcome"]
  in
  ()
