(** Cancellation and finalizers: Suspension: never suspends in native Unix/input
    forwarding; these domain-blocking calls are not Eio suspension points; native
    operation behavior is delegated to Unix. Cancellation: not a cancellation point in
    native forwarding; native operation behavior is delegated to Unix. Finalizers: none
    are registered; descriptor ownership stays with the caller. Locking: no lock is
    acquired. Cancellation safety: unsafe because progress is lost if native I/O stops
    after consuming or writing a prefix. Raises: native calls delegate exception behavior
    to Unix and propagate [Unix.Unix_error] and input-channel failures unchanged. These
    compile-only fixtures are not production complete-transfer wrappers. ^safe-jwwj
    ^safe-qmcw ^safe-t50j ^safe-fr73 *)

val read : Unix.file_descr -> bytes -> int
(** Compile-only count-rule fixtures; these functions are not executed. ^safe-jwwj
    ^safe-qmcw ^safe-t50j ^safe-fr73 *)

val used : Unix.file_descr -> bytes -> int
val eof : Unix.file_descr -> bytes -> int option
val tuple : Unix.file_descr -> bytes -> int
val alias_tuple : Unix.file_descr -> bytes -> Unix.sockaddr * (int * Unix.sockaddr)
val partial : Unix.file_descr -> unit
val unrelated : unit -> unit
val unknown : ('a -> 'b -> int -> int -> 'c) -> 'a -> 'b -> unit
val shadow : 'a -> 'b -> unit

module Fake : sig
  val write : 'a -> 'b -> 'c -> 'd -> int
end

module Alias = Fake

val fake_alias : 'a -> 'b -> unit
val fake_unix : 'a -> 'b -> unit
val fake_ignore : Unix.file_descr -> bytes -> int
val fake_ignore_module : Unix.file_descr -> bytes -> int

val forward :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > ->
  Unix.file_descr ->
  bytes ->
  int ->
  int ->
  int

val wrapper :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > -> Unix.file_descr -> bytes -> int

val renamed_wrapper :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > -> 'a -> 'b -> unit

val transform : Unix.file_descr -> bytes -> int -> int -> int
val transformed_wrapper : Unix.file_descr -> bytes -> unit

val complete :
  [> Eio.Flow.source_ty ] Eio.Flow.source -> [> Eio.Flow.sink_ty ] Eio.Flow.sink -> unit
(** Suspension: may suspend in [Eio.Flow.copy], depending on the supplied source and sink
    implementations. Cancellation: depends on [Eio.Flow.copy] and the supplied source and
    sink. Finalizers: none are added; caller retains flow ownership. Locking: none is
    added; synchronization is delegated to the flows. Cancellation safety: unsafe because
    progress is lost after a consumed prefix. Raises: exceptions from [Eio.Flow.copy] and
    supplied source/sink implementations propagate unchanged. ^safe-fr73 *)

val write_loop : Unix.file_descr -> bytes -> unit
val consumed_then_ignored : Unix.file_descr -> bytes -> int
val returned_alias : Unix.file_descr -> bytes -> int
val shadowed_ignore_count : Unix.file_descr -> bytes -> int
val shadowed_operation_count : 'a -> 'b -> unit
val heap_retained : Unix.file_descr -> bytes -> unit
