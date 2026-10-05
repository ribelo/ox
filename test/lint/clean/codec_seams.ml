(* ^safe-1kqm: alias of a real, validated published domain. *)
type t = Ox_http.Url.t

let parse = Ox_http.Url.parse
