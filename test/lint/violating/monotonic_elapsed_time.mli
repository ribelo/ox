val elapsed : _ Eio.Time.clock -> float
val expired : _ Eio.Time.clock -> bool
val sleep : _ Eio.Time.clock -> unit
val timeout : _ Eio.Time.clock -> (unit, [ `Timeout ]) result
val caps_elapsed : caps:< Ox_caps.Cap.time ; .. > -> float
