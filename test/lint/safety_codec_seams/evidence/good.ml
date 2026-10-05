type url = Ox_http.Url.t
type name = Ox_http.Header.name
type limit = Ox_observability.Logger.limit
type config = Ox_otel.Meter.histogram_config
type secret = Ox_observability.Redact.t
type 'a envelope = { payload : 'a option }
type tree = Leaf of url | Node of tree list
module type Safe = sig val use : callback:(url -> unit) -> url envelope end
module Yojson = struct module Safe = struct type t = string end end
type same_name = Yojson.Safe.t
