[@@@ox.domain]

type t = Ox_http.Url.t

val parse : string -> (t, Ox_http.Url.parse_error) result
