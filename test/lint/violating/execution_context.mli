val broken : Ox_blocking.Pool.t -> (unit, [ `Shutting_down ]) result
val result : Ox_blocking.Pool.t -> (unit, [ `Shutting_down | `Callback of unit ]) result
