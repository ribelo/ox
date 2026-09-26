(** A Service's status, read from its live state. Pure: no cancellation or finalizers. *)
type state = Ok | Degraded of string | Failed of string
type t = { name : string; state : state; details : (string * string) list }
val make : ?details:(string * string) list -> string -> state -> t
(** Construct a status without taking ownership of any resources. *)
