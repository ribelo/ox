(** Cancellation and finalizers: Suspension: never suspends in native Unix/input
    forwarding; these domain-blocking calls are not Eio suspension points;
    native operation behavior is delegated to Unix. Cancellation: not a
    cancellation point in native forwarding; native operation behavior is
    delegated to Unix. Finalizers: none are registered; descriptor ownership
    stays with the caller. Locking: no lock is acquired. Cancellation safety:
    unsafe because progress is lost if native I/O stops after consuming or
    writing a prefix. Raises: native calls delegate exception behavior to Unix
    and propagate [Unix.Unix_error] and input-channel failures unchanged. These
    compile-only fixtures are not production complete-transfer wrappers.
    ^safe-jwwj ^safe-qmcw ^safe-t50j ^safe-fr73 *)

val read : Unix.file_descr -> bytes -> unit
(** Compile-only count-rule fixtures; these functions are not executed.
    ^safe-jwwj ^safe-qmcw ^safe-t50j ^safe-fr73 *)

val write : Unix.file_descr -> bytes -> unit
val single_write : Unix.file_descr -> bytes -> unit
val recv : Unix.file_descr -> bytes -> unit
val send : Unix.file_descr -> bytes -> unit
val recvfrom : Unix.file_descr -> bytes -> Unix.sockaddr
val unused_tuple : Unix.file_descr -> bytes -> Unix.sockaddr
val sendto : Unix.file_descr -> bytes -> Unix.sockaddr -> unit
val input : in_channel -> bytes -> unit
val shadowed_count : Unix.file_descr -> bytes -> int
val full_tuple : Unix.file_descr -> bytes -> unit

module Native = Unix

val module_alias : Native.file_descr -> bytes -> unit
val local_alias : Unix.file_descr -> bytes -> unit
val opened : Unix.file_descr -> bytes -> unit
val discard : 'a -> unit
val ignore_alias : Unix.file_descr -> bytes -> unit

val forward :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > ->
  Unix.file_descr ->
  bytes ->
  int ->
  int ->
  int

val wrapper :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > ->
  Unix.file_descr ->
  bytes ->
  unit

val wrapper_alias :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > ->
  Unix.file_descr ->
  bytes ->
  unit

val wrapped_receive :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > ->
  Unix.file_descr ->
  bytes ->
  int ->
  int ->
  Unix.msg_flag list ->
  int * Unix.sockaddr

val wrapper_tuple :
  caps:< fs_read : Ox_caps.Cap.Token.fs_read ; .. > ->
  Unix.file_descr ->
  bytes ->
  Unix.sockaddr

module Forward : sig
  val write : Unix.file_descr -> bytes -> int -> int -> int
end

module Forward_alias = Forward

val module_wrapper : Unix.file_descr -> bytes -> unit
val apply_ignore : Unix.file_descr -> bytes -> unit
val pipe_ignore : Unix.file_descr -> bytes -> unit
val bound_ignore : Unix.file_descr -> bytes -> unit
val result_alias : Unix.file_descr -> bytes -> unit
val local_ignore_alias : Unix.file_descr -> bytes -> unit
val tuple_ignore : Unix.file_descr -> bytes -> Unix.sockaddr
val whole_tuple_alias : Unix.file_descr -> bytes -> unit
val alias_wildcard : Unix.file_descr -> bytes -> unit
