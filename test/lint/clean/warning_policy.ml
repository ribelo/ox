(* ^safe-tpzm: clean canonical warning-policy evidence. *)
[@@@ocaml.warning "-P+8"]
[@@@ocaml.warnerror "-8+P"]

let value = 1 [@@warning "+8"] [@@warning "-8"]
