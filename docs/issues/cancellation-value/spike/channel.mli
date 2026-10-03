type ('a, 'e) t
val create : ?capacity:int -> unit -> ('a, 'e) t
val send : ('a, 'e) t -> 'a -> (unit, [> `Done | `Error of 'e ]) result
val receive : cancel:Cancellation.t @ local -> ('a, 'e) t -> ('a, [> `Canceled | `Done | `Error of 'e ]) result
val done_ : ('a, 'e) t -> unit
val error : ('a, 'e) t -> 'e -> unit
