val sleep : _ Eio.Time.clock -> (float -> float) -> unit
val compare : _ Eio.Time.clock -> (float -> float) -> bool
val fractional : _ Eio.Time.clock -> (float -> float) -> float
val different_reads : _ Eio.Time.clock -> float
