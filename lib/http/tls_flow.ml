module Ssl = Ox_http_tls_openssl

exception Tls_failure of string

type t = { raw : Eio.Flow.two_way_ty Eio.Resource.t; ssl : Ssl.ssl; wire : Cstruct.t }

let fail { Ssl.code; detail } =
  raise
    (Tls_failure
       (Printf.sprintf "OpenSSL error %d%s" code
          (match detail with None -> "" | Some text -> ": " ^ text)))

let rec drain t =
  if Ssl.bio_write_pending t.ssl > 0 then (
    let n = Ssl.bio_read t.ssl (Cstruct.to_bigarray t.wire) 0 (Cstruct.length t.wire) in
    if n <= 0 then raise (Tls_failure "OpenSSL BIO drain failed");
    Eio.Flow.write t.raw [ Cstruct.sub t.wire 0 n ];
    drain t)

let feed t =
  let n = Eio.Flow.single_read t.raw t.wire in
  let rec loop off =
    if off < n then (
      let written = Ssl.bio_write t.ssl (Cstruct.to_bigarray t.wire) off (n - off) in
      if written <= 0 then raise (Tls_failure "OpenSSL BIO feed failed");
      loop (off + written))
  in
  loop 0

let handshake t =
  let rec loop () =
    match Ssl.handshake t.ssl with
    | Ssl.Handshake_ok -> drain t
    | Ssl.Handshake_error ({ code = 2; _ } as e) ->
        drain t;
        (try feed t with End_of_file -> fail e);
        loop ()
    | Ssl.Handshake_error ({ code = 3; _ } as e) ->
        if Ssl.bio_write_pending t.ssl = 0 then fail e;
        drain t;
        loop ()
    | Ssl.Handshake_error e -> fail e
  in
  loop ();
  if Ssl.get_verify_result t.ssl <> 0 then
    raise
      (Tls_failure
         (Printf.sprintf "certificate verification failed: %d"
            (Ssl.get_verify_result t.ssl)))

let single_read t dst =
  let n = Cstruct.length dst in
  if n = 0 then invalid_arg "TLS read: zero-length buffer";
  let rec loop () =
    let chunk = min n 16384 in
    let plain = Cstruct.create chunk in
    match Ssl.read t.ssl (Cstruct.to_bigarray plain) 0 chunk with
    | Ssl.Io_bytes bytes when bytes > 0 ->
        Cstruct.blit plain 0 dst 0 bytes;
        bytes
    | Ssl.Io_bytes _ -> raise End_of_file
    | Ssl.Io_error { code = 6; _ } -> raise End_of_file
    | Ssl.Io_error ({ code = 2; _ } as e) ->
        drain t;
        (try feed t with End_of_file -> fail e);
        loop ()
    | Ssl.Io_error ({ code = 3; _ } as e) ->
        if Ssl.bio_write_pending t.ssl = 0 then fail e;
        drain t;
        loop ()
    | Ssl.Io_error e -> fail e
  in
  loop ()

let single_write t bufs =
  match bufs with
  | [] -> 0
  | first :: _ ->
      let len = min 16384 (Cstruct.length first) in
      if len = 0 then invalid_arg "TLS write: zero-length buffer";
      let rec loop () =
        match Ssl.write t.ssl (Cstruct.to_bigarray first) 0 len with
        | Ssl.Io_bytes n when n > 0 ->
            drain t;
            n
        | Ssl.Io_bytes _ -> raise (Tls_failure "TLS write returned zero")
        | Ssl.Io_error ({ code = 2; _ } as e) ->
            drain t;
            (try feed t with End_of_file -> fail e);
            loop ()
        | Ssl.Io_error ({ code = 3; _ } as e) ->
            if Ssl.bio_write_pending t.ssl = 0 then fail e;
            drain t;
            loop ()
        | Ssl.Io_error e -> fail e
      in
      loop ()

module Pi = struct
  type nonrec t = t

  let read_methods = []
  let single_read = single_read
  let single_write = single_write
  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
  let shutdown t command = Eio.Flow.shutdown t.raw command
end

let create ~raw ~ssl =
  let t = { raw; ssl; wire = Cstruct.create 16384 } in
  handshake t;
  Eio.Resource.T (t, Eio.Flow.Pi.two_way (module Pi))
