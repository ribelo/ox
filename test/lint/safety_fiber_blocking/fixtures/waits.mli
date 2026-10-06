(** ^safe-9ved ^safe-r5ye: compiler-only operation matrix; no fixture body executes. *)
val thread : Thread.t -> unit -> unit
val domain : 'a Domain.t -> unit -> unit
val read : unit -> unit
val write : unit -> unit
val nonblock : unit -> unit
val cleared : unit -> unit
val set : unit -> unit
val unknown : Unix.file_descr -> unit -> unit
val native : pool:Ox_blocking.Pool.t -> unit -> unit
val transfer : ((unit -> unit) -> unit) -> unit -> unit
val unrelated : (Eio_unix.Stdenv.base -> 'a) -> unit -> unit
val partial : Unix.file_descr -> unit -> unit
val imported_native : pool:Ox_blocking.Pool.t -> unit -> unit
val imported_partial : unit -> unit
val conditional : bool -> unit -> unit
