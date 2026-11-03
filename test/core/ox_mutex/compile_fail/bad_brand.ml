(* ^ncrit-1px5 ^ncrit-lpe4: another mutex's access is refused. *)
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

let wrong () =
  let (Ox.Mutex.P m1) = Ox.Mutex.create () in
  let (Ox.Mutex.P m2) = Ox.Mutex.create () in
  let c = Counter.make m1 in
  Ox.Mutex.with_access m2 (fun a -> Counter.incr a c)
