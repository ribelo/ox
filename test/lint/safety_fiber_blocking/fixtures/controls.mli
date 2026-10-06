val run_native : pool:Ox_blocking.Pool.t -> (unit -> unit) -> (unit, [ `Shutting_down ]) result
val non_eio : unit -> unit
val worker : pool:Ox_blocking.Pool.t -> unit -> unit
val dormant : unit -> unit
val harmless : unit -> unit
module Shadow : sig val run : unit -> unit end
val partial_worker : unit -> unit
val partial_protect : unit -> unit
val partial_fork : unit -> unit
val timer_loop : clock:_ Eio.Time.clock -> unit -> unit
