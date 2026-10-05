val read : int Atomic.t -> unit
val write : int Atomic.t -> unit
val callback : (unit -> bool) Atomic.t -> unit
