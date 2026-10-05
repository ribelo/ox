(* ^nderive-p4tq: a domain type named result cannot capture the decode channel. *)
type result = { value : int } [@@deriving yojson]
type envelope = { payload : result } [@@deriving yojson]
