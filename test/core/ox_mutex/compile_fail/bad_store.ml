(* ^ncrit-1px5 ^ncrit-lpe4: the access cannot be stored. *)
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

let store (type k) (m : k Ox.Mutex.t) (r : k Ox.Mutex.Access.t option ref) =
  Ox.Mutex.with_access m (fun a -> r := Some a)
