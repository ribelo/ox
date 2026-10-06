val direct : unit -> 'a
val alias : unit -> 'a
val helper : unit -> 'a
val server : [> `Generic | `Unix ] Eio.Net.listening_socket -> unit
val mutex : Eio.Mutex.t -> 'a
val release : Eio.Switch.t -> unit
val substituted : unit -> 'a
val direct_value : unit -> 'a
