(* ^ncrit-1px5 ^ncrit-lpe4: a fork cannot capture the access. *)
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

let fork (type k) scope (m : k Ox.Mutex.t) (c : k Counter.t) =
  Ox.Mutex.with_access_waiting m (fun a -> Ox.Scope.fork scope (fun () -> Counter.incr a c))
