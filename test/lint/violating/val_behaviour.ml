(* ^nlintd-truth: negative shape evidence has a real implementation. *)
let missing _ = ()
module Clock = Eio.Time.Mono
type 'a deps = { caps : < Ox_caps.Cap.env >; clock : 'a Clock.t }
let nested _ = ()
let flow _ = ()
let incomplete _ = ()
module Local = struct module Switch = struct type t = int end let pure x = x end
let dotted _ = ()
let duplicate _ = ()
let missing_period _ = ()
let marker _ = ()
