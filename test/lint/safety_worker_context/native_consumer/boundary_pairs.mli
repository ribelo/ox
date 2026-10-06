val helper : ?_unused:unit -> unit -> unit
val optional : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val dormant : unit -> pool:Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val applied : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val overridden : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val matched : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val forwarded : Ox_blocking.Pool.t -> (unit -> unit option) -> (unit, [ `Shutting_down ]) result
