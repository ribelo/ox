[@@@ox.domain]
module Ox_http : sig module Url : sig type t val parse : string -> (t, string) result end end
type t = Ox_http.Url.t
