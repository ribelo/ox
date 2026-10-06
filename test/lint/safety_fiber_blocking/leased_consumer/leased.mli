val native : pool:Ox_blocking.Pool.t -> unit -> unit
val release_wait : pool:Ox_blocking.Pool.t -> unit -> unit
val cancel_wait : pool:Ox_blocking.Pool.t -> unit -> unit
val computed_release : pool:Ox_blocking.Pool.t -> unit -> unit
val opaque_release : pool:Ox_blocking.Pool.t -> ((unit, 'e) result Ox_blocking.lease_end -> unit) -> unit -> unit
val missing_release : pool:Ox_blocking.Pool.t -> unit -> unit
val missing_pool : unit -> unit
val native_alias : pool:Ox_blocking.Pool.t -> unit -> unit
val counting_native : pool:Ox_blocking.Pool.t -> Semaphore.Counting.t -> unit -> unit
val counting_owner : Semaphore.Counting.t -> unit -> unit
val counting_release : pool:Ox_blocking.Pool.t -> Semaphore.Counting.t -> unit -> unit
