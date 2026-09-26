type state = Ok | Degraded of string | Failed of string
type t = { name : string; state : state; details : (string * string) list }

let make ?(details = []) name state = { name; state; details }
