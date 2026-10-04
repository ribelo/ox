module Ssl = Ox_http_tls_openssl

exception Tls_failure of string

let failure_message = function Tls_failure message -> Some message | _ -> None

module Testing = struct
  let failure message = Tls_failure message
end

type ty = [ Eio.Flow.two_way_ty | Eio.Resource.close_ty ]

(* wsduplex-j4rn: one receiver and concurrent senders share this flow.
   [inbound] stays live for a raw read, including while that read is parked.
   [outbound] stays live for a raw write. They never alias.

   [read_mu] covers only the parked raw read and the record-boundary state.
   [write_mu] serializes writers and covers the parked raw write, so
   ciphertext records are not byte-interleaved. It is never held across a
   raw read, and a sender does not take [read_mu] on the success path, so an
   idle read cannot block a send.

   [ssl_mu] covers SSL and BIO calls only. OpenSSL's SSL object is not safe
   for overlapping calls. The lock is never held across a socket operation,
   so a writer is not queued behind a parked read. Expected failures unlock
   rather than poison: the other direction and close still have to run. *)

let wire_capacity = 16384
let want_read = 2
let want_write = 3
let zero_return = 6

type t = {
  raw : ty Eio.Resource.t;
  ssl : Ssl.ssl;
  inbound : Cstruct.t;
  outbound : Cstruct.t;
  read_mu : Eio.Mutex.t;
  write_mu : Eio.Mutex.t;
  ssl_mu : Eio.Mutex.t;
  mutable header_bytes : int;
  mutable record_length : int;
  mutable record_left : int;
  mutable closed : bool;
}

let fail { Ssl.code; detail } =
  raise
    (Tls_failure
       (Printf.sprintf "OpenSSL error %d%s" code
          (match detail with None -> "" | Some text -> ": " ^ text)))

let with_lock lock f = Eio.Mutex.use_ro lock f

(* Caller holds [write_mu]. [outbound] is exclusive until each raw write returns. *)
let drain t =
  let rec loop () =
    let n =
      with_lock t.ssl_mu (fun () ->
          if Ssl.bio_write_pending t.ssl = 0 then 0
          else
            let n =
              Ssl.bio_read t.ssl
                (Cstruct.to_bigarray t.outbound)
                0 (Cstruct.length t.outbound)
            in
            if n <= 0 then raise (Tls_failure "OpenSSL BIO drain failed");
            n)
    in
    if n > 0 then (
      Eio.Flow.write t.raw [ Cstruct.sub t.outbound 0 n ];
      loop ())
  in
  loop ()

let flush t = with_lock t.write_mu (fun () -> drain t)

(* A reader must not wait for a writer blocked in a raw write: that writer
   already owns the in-flight ciphertext, and waiting would stall the read
   that frees the TCP window. *)
let try_flush t =
  let pending = with_lock t.ssl_mu (fun () -> Ssl.bio_write_pending t.ssl) in
  if pending > 0 && Eio.Mutex.try_lock t.write_mu then
    Fun.protect ~finally:(fun () -> Eio.Mutex.unlock t.write_mu) (fun () -> drain t)

(* nhttp-7pp8: OpenSSL's WANT_READ does not distinguish an empty read BIO
   from a partially consumed TLS record. Track only wire framing; OpenSSL
   remains responsible for authenticating and validating every record. *)
let track_records t n =
  let rec loop off =
    if off < n then (
      if t.record_left > 0 then (
        let count = min t.record_left (n - off) in
        t.record_left <- t.record_left - count;
        loop (off + count))
      else
        let byte = Cstruct.get_uint8 t.inbound off in
        if t.header_bytes = 4 then (
          t.record_left <- t.record_length lor byte;
          t.header_bytes <- 0)
        else (
          if t.header_bytes = 3 then t.record_length <- byte lsl 8;
          t.header_bytes <- t.header_bytes + 1);
        loop (off + 1))
  in
  loop 0

(* Caller holds [read_mu], never [write_mu] or [ssl_mu]. The raw read may
   park; the bytes it returns are fed before this function yields again so
   cancellation cannot drop a consumed record. *)
let feed t =
  let n = Eio.Flow.single_read t.raw t.inbound in
  Eio.Cancel.protect (fun () ->
      with_lock t.ssl_mu (fun () ->
          track_records t n;
          let rec loop off =
            if off < n then (
              let written =
                Ssl.bio_write t.ssl (Cstruct.to_bigarray t.inbound) off (n - off)
              in
              if written <= 0 then raise (Tls_failure "OpenSSL BIO feed failed");
              loop (off + written))
          in
          loop 0))

let handshake t =
  let rec loop () =
    match with_lock t.ssl_mu (fun () -> Ssl.handshake t.ssl) with
    | Ssl.Handshake_ok -> flush t
    | Ssl.Handshake_error ({ code; _ } as e) when code = want_read ->
        flush t;
        (try with_lock t.read_mu (fun () -> feed t) with End_of_file -> fail e);
        loop ()
    | Ssl.Handshake_error ({ code; _ } as e) when code = want_write ->
        if with_lock t.ssl_mu (fun () -> Ssl.bio_write_pending t.ssl) = 0 then fail e;
        flush t;
        loop ()
    | Ssl.Handshake_error e -> fail e
  in
  loop ();
  let verify = with_lock t.ssl_mu (fun () -> Ssl.get_verify_result t.ssl) in
  if verify <> 0 then
    raise (Tls_failure (Printf.sprintf "certificate verification failed: %d" verify))

let single_read t dst =
  let n = Cstruct.length dst in
  if n = 0 then invalid_arg "TLS read: zero-length buffer";
  let rec loop () =
    let chunk = min n 16384 in
    let plain = Cstruct.create chunk in
    match
      with_lock t.ssl_mu (fun () -> Ssl.read t.ssl (Cstruct.to_bigarray plain) 0 chunk)
    with
    | Ssl.Io_bytes bytes when bytes > 0 ->
        Cstruct.blit plain 0 dst 0 bytes;
        bytes
    | Ssl.Io_bytes _ -> raise End_of_file
    | Ssl.Io_error { code; _ } when code = zero_return -> raise End_of_file
    | Ssl.Io_error { code; _ } when code = want_read ->
        try_flush t;
        (try with_lock t.read_mu (fun () -> feed t)
         with End_of_file ->
           if t.header_bytes = 0 && t.record_left = 0 then raise End_of_file
           else raise (Tls_failure "TLS peer closed with a truncated record"));
        loop ()
    | Ssl.Io_error ({ code; _ } as e) when code = want_write ->
        let pending = with_lock t.ssl_mu (fun () -> Ssl.bio_write_pending t.ssl) in
        if pending = 0 then fail e;
        if Eio.Mutex.try_lock t.write_mu then
          Fun.protect ~finally:(fun () -> Eio.Mutex.unlock t.write_mu) (fun () -> drain t)
        else Eio.Fiber.yield ();
        loop ()
    | Ssl.Io_error e -> fail e
  in
  loop ()

let write_once t first len =
  with_lock t.write_mu (fun () ->
      match
        with_lock t.ssl_mu (fun () -> Ssl.write t.ssl (Cstruct.to_bigarray first) 0 len)
      with
      | Ssl.Io_bytes n when n > 0 ->
          drain t;
          `Wrote n
      | Ssl.Io_bytes _ -> raise (Tls_failure "TLS write returned zero")
      | Ssl.Io_error ({ code; _ } as e) when code = want_read ->
          drain t;
          `Want_read e
      | Ssl.Io_error ({ code; _ } as e) when code = want_write ->
          if with_lock t.ssl_mu (fun () -> Ssl.bio_write_pending t.ssl) = 0 then fail e;
          drain t;
          `Again
      | Ssl.Io_error e -> fail e)

let single_write t bufs =
  match bufs with
  | [] -> 0
  | first :: _ ->
      let len = min 16384 (Cstruct.length first) in
      if len = 0 then invalid_arg "TLS write: zero-length buffer";
      let rec attempt () =
        match write_once t first len with
        | `Wrote n -> n
        | `Again -> attempt ()
        | `Want_read e ->
            (* Lock released before the raw read, so other writers are not
               stuck behind it. A parked receiver already holds [read_mu];
               waiting here only happens when OpenSSL itself needs inbound
               ciphertext before this write can continue. *)
            (try with_lock t.read_mu (fun () -> feed t) with End_of_file -> fail e);
            attempt ()
      in
      attempt ()

(* nhttp-rs5p: send our close_notify without waiting for the peer's reply,
   and release the socket even if sending the alert fails or is cancelled. *)
let close t =
  if not t.closed then (
    t.closed <- true;
    Fun.protect
    (* ^nlintc-g6k3: raw providers may suspend while closing; protect only that cleanup. *)
      ~finally:(fun () -> Eio.Cancel.protect (fun () -> Eio.Flow.close t.raw))
      (fun () ->
        with_lock t.write_mu (fun () ->
            let result = with_lock t.ssl_mu (fun () -> Ssl.shutdown t.ssl) in
            drain t;
            if result < 0 then raise (Tls_failure "OpenSSL TLS shutdown failed"))))

module Pi = struct
  type nonrec t = t

  let read_methods = []
  let single_read = single_read
  let single_write = single_write
  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
  let shutdown t command = Eio.Flow.shutdown t.raw command
end

let create ~raw ~ssl =
  let t =
    {
      raw;
      ssl;
      inbound = Cstruct.create wire_capacity;
      outbound = Cstruct.create wire_capacity;
      read_mu = Eio.Mutex.create ();
      write_mu = Eio.Mutex.create ();
      ssl_mu = Eio.Mutex.create ();
      header_bytes = 0;
      record_length = 0;
      record_left = 0;
      closed = false;
    }
  in
  handshake t;
  let handler : (t, ty) Eio.Resource.handler =
    Eio.Resource.handler
      (Eio.Resource.H (Eio.Resource.Close, close)
      :: Eio.Resource.bindings (Eio.Flow.Pi.two_way (module Pi)))
  in
  Eio.Resource.T (t, handler)
