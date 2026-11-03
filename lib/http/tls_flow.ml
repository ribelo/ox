module Ssl = Ox_http_tls_openssl
module M = Ox.Mutex

exception Tls_failure of string

let failure_message = function Tls_failure message -> Some message | _ -> None

module Testing = struct
  let failure message = Tls_failure message
end

type ty = [ Eio.Flow.two_way_ty | Eio.Resource.close_ty ]

(* wsduplex-j4rn: one receiver and concurrent senders share this flow.
   ^nduplex-87sz ^nduplex-6d16: each piece of TLS state has the brand of the
   Ox.Mutex that guards it, so reaching it without that lock, or under
   another lock, does not compile.

   [read_mu] guards [Inbound]: the ciphertext buffer of a raw read, live
   while that read is parked, and the record-boundary state.
   [write_mu] guards [Outbound]: the ciphertext buffer of a raw write. It
   serializes writers so ciphertext records are not byte-interleaved. It is
   never held across a raw read, and a sender does not take [read_mu] on the
   success path, so an idle read cannot block a send.

   [ssl_mu] guards [Engine], OpenSSL's SSL object, which both directions
   really share: it is not safe for overlapping calls, a read can leave output
   that must be flushed, and a write can need inbound ciphertext first. The
   lock is never held across a socket operation, so a writer is not queued
   behind a parked read. Expected failures unlock rather than poison: the
   other direction and close still have to run. *)

let wire_capacity = 16384
let want_read = 2
let want_write = 3
let zero_return = 6

let fail { Ssl.code; detail } =
  raise
    (Tls_failure
       (Printf.sprintf "OpenSSL error %d%s" code
          (match detail with None -> "" | Some text -> ": " ^ text)))

module Engine : sig
  type 's t

  val make : 's M.t -> Ssl.ssl -> 's t
  val handshake : 's M.Access.t @ local -> 's t -> Ssl.handshake_result
  val verify_result : 's M.Access.t @ local -> 's t -> int
  val read : 's M.Access.t @ local -> 's t -> Cstruct.t -> int -> Ssl.io_result
  val write : 's M.Access.t @ local -> 's t -> Cstruct.t -> int -> Ssl.io_result
  val shutdown : 's M.Access.t @ local -> 's t -> int
  val write_pending : 's M.Access.t @ local -> 's t -> int
  val bio_read : 's M.Access.t @ local -> 's t -> Cstruct.t -> int
  val bio_write : 's M.Access.t @ local -> 's t -> Cstruct.t -> int -> int -> int
end = struct
  type 's t = Ssl.ssl

  let make _ ssl = ssl
  let handshake _ ssl = Ssl.handshake ssl
  let verify_result _ ssl = Ssl.get_verify_result ssl
  let read _ ssl plain len = Ssl.read ssl (Cstruct.to_bigarray plain) 0 len
  let write _ ssl plain len = Ssl.write ssl (Cstruct.to_bigarray plain) 0 len
  let shutdown _ ssl = Ssl.shutdown ssl
  let write_pending _ ssl = Ssl.bio_write_pending ssl

  let bio_read _ ssl buffer =
    Ssl.bio_read ssl (Cstruct.to_bigarray buffer) 0 (Cstruct.length buffer)

  let bio_write _ ssl buffer off len = Ssl.bio_write ssl (Cstruct.to_bigarray buffer) off len
end

module Inbound : sig
  type 'r t

  val make : 'r M.t -> 'r t
  val read_raw : 'r M.Access.t @ local -> 'r t -> ty Eio.Resource.t -> int

  val feed :
    'r M.Access.t @ local -> 'r t -> 's M.Access.t @ local -> 's Engine.t -> int -> unit

  val at_record_boundary : 'r M.Access.t @ local -> 'r t -> bool
end = struct
  type 'r t = {
    buffer : Cstruct.t;
    mutable header_bytes : int;
    mutable record_length : int;
    mutable record_left : int;
  }

  let make _ =
    { buffer = Cstruct.create wire_capacity; header_bytes = 0; record_length = 0; record_left = 0 }

  let read_raw _ t raw = Eio.Flow.single_read raw t.buffer

  (* nhttp-7pp8: OpenSSL's WANT_READ does not distinguish an empty read BIO
     from a partially consumed TLS record. Track only wire framing; OpenSSL
     remains responsible for authenticating and validating every record. *)
  let track t n =
    let rec loop off =
      if off < n then (
        if t.record_left > 0 then (
          let count = min t.record_left (n - off) in
          t.record_left <- t.record_left - count;
          loop (off + count))
        else
          let byte = Cstruct.get_uint8 t.buffer off in
          if t.header_bytes = 4 then (
            t.record_left <- t.record_length lor byte;
            t.header_bytes <- 0)
          else (
            if t.header_bytes = 3 then t.record_length <- byte lsl 8;
            t.header_bytes <- t.header_bytes + 1);
          loop (off + 1))
    in
    loop 0

  let feed _ t sa engine n =
    track t n;
    let rec loop off =
      if off < n then (
        let written = Engine.bio_write sa engine t.buffer off (n - off) in
        if written <= 0 then raise (Tls_failure "OpenSSL BIO feed failed");
        loop (off + written))
    in
    loop 0 [@nontail]

  let at_record_boundary _ t = t.header_bytes = 0 && t.record_left = 0
end

module Outbound : sig
  type 'w t

  val make : 'w M.t -> 'w t

  val drain :
    'w M.Access.t @ local -> 'w t -> 's M.t -> 's Engine.t -> ty Eio.Resource.t -> unit
end = struct
  type 'w t = Cstruct.t

  let make _ = Cstruct.create wire_capacity

  (* The caller's [write_mu] section keeps [buffer] exclusive until each raw
     write returns. *)
  let drain _ buffer ssl_mu engine raw =
    let rec loop () =
      let n =
        M.with_access ssl_mu (fun sa ->
            if Engine.write_pending sa engine = 0 then 0
            else
              let n = Engine.bio_read sa engine buffer in
              if n <= 0 then raise (Tls_failure "OpenSSL BIO drain failed");
              n)
      in
      if n > 0 then (
        Eio.Flow.write raw [ Cstruct.sub buffer 0 n ];
        loop ())
    in
    loop ()
end

type ('r, 'w, 's) state = {
  raw : ty Eio.Resource.t;
  read_mu : 'r M.t;
  inbound : 'r Inbound.t;
  write_mu : 'w M.t;
  outbound : 'w Outbound.t;
  ssl_mu : 's M.t;
  engine : 's Engine.t;
  mutable closed : bool;
}

type t = T : ('r, 'w, 's) state -> t

let drain wa s = Outbound.drain wa s.outbound s.ssl_mu s.engine s.raw
let flush s = M.with_access_waiting s.write_mu (fun wa -> drain wa s) [@nontail]
let pending s = M.with_access s.ssl_mu (fun sa -> Engine.write_pending sa s.engine)

(* A reader must not wait for a writer blocked in a raw write: that writer
   already owns the in-flight ciphertext, and waiting would stall the read
   that frees the TCP window. *)
let try_flush s =
  if pending s > 0 then
    match M.try_with_access_waiting s.write_mu (fun wa -> drain wa s) with
    | Some () | None -> ()

(* Caller holds [read_mu], never [write_mu] or [ssl_mu]. The raw read may
   park; the bytes it returns are fed under a cancellation-shielded [ssl_mu]
   acquisition before this function yields again, so cancellation cannot drop
   a consumed record. *)
let feed ra s =
  let n = Inbound.read_raw ra s.inbound s.raw in
  M.with_access_protected s.ssl_mu (fun sa -> Inbound.feed ra s.inbound sa s.engine n)
  [@nontail]

let feed_or_fail s e =
  try M.with_access_waiting s.read_mu (fun ra -> feed ra s) with End_of_file -> fail e

let handshake s =
  let rec loop () =
    match M.with_access s.ssl_mu (fun sa -> Engine.handshake sa s.engine) with
    | Ssl.Handshake_ok -> flush s
    | Ssl.Handshake_error ({ code; _ } as e) when code = want_read ->
        flush s;
        feed_or_fail s e;
        loop ()
    | Ssl.Handshake_error ({ code; _ } as e) when code = want_write ->
        if pending s = 0 then fail e;
        flush s;
        loop ()
    | Ssl.Handshake_error e -> fail e
  in
  loop ();
  let verify = M.with_access s.ssl_mu (fun sa -> Engine.verify_result sa s.engine) in
  if verify <> 0 then
    raise (Tls_failure (Printf.sprintf "certificate verification failed: %d" verify))

let single_read (T s) dst =
  let n = Cstruct.length dst in
  if n = 0 then invalid_arg "TLS read: zero-length buffer";
  let rec loop () =
    let chunk = min n 16384 in
    let plain = Cstruct.create chunk in
    match M.with_access s.ssl_mu (fun sa -> Engine.read sa s.engine plain chunk) with
    | Ssl.Io_bytes bytes when bytes > 0 ->
        Cstruct.blit plain 0 dst 0 bytes;
        bytes
    | Ssl.Io_bytes _ -> raise End_of_file
    | Ssl.Io_error { code; _ } when code = zero_return -> raise End_of_file
    | Ssl.Io_error { code; _ } when code = want_read -> (
        try_flush s;
        match
          M.with_access_waiting s.read_mu (fun ra ->
              match feed ra s with
              | () -> `Fed
              | exception End_of_file ->
                  if Inbound.at_record_boundary ra s.inbound then `Eof else `Truncated)
        with
        | `Fed -> loop ()
        | `Eof -> raise End_of_file
        | `Truncated -> raise (Tls_failure "TLS peer closed with a truncated record"))
    | Ssl.Io_error ({ code; _ } as e) when code = want_write ->
        if pending s = 0 then fail e;
        (match M.try_with_access_waiting s.write_mu (fun wa -> drain wa s) with
        | Some () -> ()
        | None -> Eio.Fiber.yield ());
        loop ()
    | Ssl.Io_error e -> fail e
  in
  loop ()

let write_once s first len =
  M.with_access_waiting s.write_mu (fun wa ->
      match M.with_access s.ssl_mu (fun sa -> Engine.write sa s.engine first len) with
      | Ssl.Io_bytes n when n > 0 ->
          drain wa s;
          `Wrote n
      | Ssl.Io_bytes _ -> raise (Tls_failure "TLS write returned zero")
      | Ssl.Io_error ({ code; _ } as e) when code = want_read ->
          drain wa s;
          `Want_read e
      | Ssl.Io_error ({ code; _ } as e) when code = want_write ->
          if pending s = 0 then fail e;
          drain wa s;
          `Again
      | Ssl.Io_error e -> fail e)
  [@nontail]

let single_write (T s) bufs =
  match bufs with
  | [] -> 0
  | first :: _ ->
      let len = min 16384 (Cstruct.length first) in
      if len = 0 then invalid_arg "TLS write: zero-length buffer";
      let rec attempt () =
        match write_once s first len with
        | `Wrote n -> n
        | `Again -> attempt ()
        | `Want_read e ->
            (* Lock released before the raw read, so other writers are not
               stuck behind it. A parked receiver already holds [read_mu];
               waiting here only happens when OpenSSL itself needs inbound
               ciphertext before this write can continue. *)
            feed_or_fail s e;
            attempt ()
      in
      attempt ()

(* nhttp-rs5p: send our close_notify without waiting for the peer's reply,
   and release the socket even if sending the alert fails or is cancelled. *)
let close (T s) =
  if not s.closed then (
    s.closed <- true;
    Fun.protect
    (* ^nlintc-g6k3: raw providers may suspend while closing; protect only that cleanup. *)
      ~finally:(fun () -> Eio.Cancel.protect (fun () -> Eio.Flow.close s.raw))
      (fun () ->
        M.with_access_waiting s.write_mu (fun wa ->
            let result = M.with_access s.ssl_mu (fun sa -> Engine.shutdown sa s.engine) in
            drain wa s;
            if result < 0 then raise (Tls_failure "OpenSSL TLS shutdown failed"))
        [@nontail]))

module Pi = struct
  type nonrec t = t

  let read_methods = []
  let single_read = single_read
  let single_write = single_write
  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
  let shutdown (T s) command = Eio.Flow.shutdown s.raw command
end

let create ~raw ~ssl =
  let (M.P read_mu) = M.create () in
  let (M.P write_mu) = M.create () in
  let (M.P ssl_mu) = M.create () in
  let s =
    {
      raw;
      read_mu;
      inbound = Inbound.make read_mu;
      write_mu;
      outbound = Outbound.make write_mu;
      ssl_mu;
      engine = Engine.make ssl_mu ssl;
      closed = false;
    }
  in
  handshake s;
  let handler : (t, ty) Eio.Resource.handler =
    Eio.Resource.handler
      (Eio.Resource.H (Eio.Resource.Close, close)
      :: Eio.Resource.bindings (Eio.Flow.Pi.two_way (module Pi)))
  in
  Eio.Resource.T (T s, handler)
