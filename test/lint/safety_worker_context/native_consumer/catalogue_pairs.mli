val callback : unit -> unit
val direct : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val invoke : (unit -> 'a) -> 'a
val higher : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val pure : ?_unused:unit -> unit -> unit
val ordinary : Ox_blocking.Pool.t -> (unit -> unit) -> (unit, [ `Shutting_down ]) result

val opaque_worker :
  Ox_blocking.Pool.t -> (unit -> unit) -> (unit, [ `Shutting_down ]) result

val escape :
  Ox_blocking.Pool.t -> ((unit -> unit) -> unit) -> (unit, [ `Shutting_down ]) result

val native : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val hooks : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val returned : Ox_blocking.Pool.t -> (unit -> unit, [ `Shutting_down ]) result
val shadow : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val unrelated : unit -> unit
