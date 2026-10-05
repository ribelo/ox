module Ox_http = struct module Url = struct type t = string let parse value = Ok value end end
type t = Ox_http.Url.t
