(* ^ncrit-1px5 ^ncrit-lpe4: the access cannot leave its section. *)
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

let outside (type k) (m : k Ox.Mutex.t) (c : k Counter.t) =
  let a = Ox.Mutex.with_access m (fun a -> a) in
  Counter.incr a c
