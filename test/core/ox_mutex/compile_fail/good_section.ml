(* ^ncrit-ihf2 ^ncrit-lpe4: state reached under its own mutex. *)
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

let count () =
  let (Ox.Mutex.P m) = Ox.Mutex.create () in
  let c = Counter.make m in
  Ox.Mutex.with_access m (fun a -> Counter.incr a c);
  Ox.Mutex.with_access m (fun a -> Counter.get a c)
