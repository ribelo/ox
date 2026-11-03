(* ^ncrit-9sfw ^ncrit-lpe4: a short section cannot use a yielding value. *)
module Counter : sig
  type 'k t

  val make : 'k Ox.Mutex.t -> 'k t
  val incr : 'k Ox.Mutex.Access.t @ local -> 'k t -> unit
  val get : 'k Ox.Mutex.Access.t @ local -> 'k t -> int
end = struct
  type 'k t = { mutable n : int }

  let make _ = { n = 0 }
  let incr _ t = t.n <- t.n + 1
  let get _ t = t.n
end

let short (type k) (m : k Ox.Mutex.t) (c : k Counter.t) (io : (unit -> unit) @ local yielding) =
  Ox.Mutex.with_access m (fun a ->
      io ();
      Counter.incr a c) [@nontail]
