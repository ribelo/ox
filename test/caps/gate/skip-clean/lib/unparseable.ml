(* ^ncaps-a27b ^ncaps-tpjy ^ncaps-rwnz: OxCaml syntax makes Semgrep partially parse this file. *)
let borrow (value @ local) = value
let safe_text = "Unix.fork () and Obj.magic are not code"
(* stdout in a comment is not a channel use. *)
