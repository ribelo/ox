(* ^safe-9ved ^safe-r5ye: compiled evidence, never execute the deliberate owner wait. *)
val owner : Semaphore.Counting.t -> unit -> unit
val worker : pool:Ox_blocking.Pool.t -> Semaphore.Counting.t -> unit -> unit
module Counting = Semaphore.Counting
val acquire : Counting.t -> unit
val alias_owner : Counting.t -> unit -> unit
val alias_worker : pool:Ox_blocking.Pool.t -> Counting.t -> unit -> unit
val outside : Counting.t -> unit -> unit
val cooperative : Eio.Semaphore.t -> unit -> unit
