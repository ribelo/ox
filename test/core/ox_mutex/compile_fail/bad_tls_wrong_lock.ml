(* ^nduplex-s3t9 ^ncrit-lpe4: Tls_flow's shape. Inbound ciphertext needs the
   read lock's access and the SSL object the SSL lock's; feeding under the
   wrong pair of locks is refused. *)
module Engine : sig
  type 's t

  val make : 's Ox.Mutex.t -> 's t
end = struct
  type 's t = unit

  let make _ = ()
end

module Inbound : sig
  type 'r t

  val make : 'r Ox.Mutex.t -> 'r t

  val feed :
    'r Ox.Mutex.Access.t @ local -> 'r t -> 's Ox.Mutex.Access.t @ local -> 's Engine.t -> unit
end = struct
  type 'r t = Bytes.t

  let make _ = Bytes.create 16
  let feed _ _ _ _ = ()
end

let swapped () =
  let (Ox.Mutex.P read_mu) = Ox.Mutex.create () in
  let (Ox.Mutex.P ssl_mu) = Ox.Mutex.create () in
  let inbound = Inbound.make read_mu and engine = Engine.make ssl_mu in
  Ox.Mutex.with_access_waiting read_mu (fun ra ->
      Ox.Mutex.with_access ssl_mu (fun sa -> Inbound.feed sa inbound ra engine))
