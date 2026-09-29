(* Copied from v1:test/http/test_tls_buffer_bounds.ml, prehandshake slices. *)
let ba n = Bigarray.Array1.create Bigarray.Char Bigarray.C_layout n

let fill buf ch =
  let cap = Bigarray.Array1.dim buf in
  for i = 0 to cap - 1 do
    Bigarray.Array1.set buf i ch
  done

let unchanged buf ch =
  let cap = Bigarray.Array1.dim buf in
  let rec loop i =
    if i = cap then true else Bigarray.Array1.get buf i = ch && loop (i + 1)
  in
  loop 0

let expect_invalid label f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> Alcotest.failf "%s: expected Invalid_argument" label

let with_prehandshake_ssl f =
  let ctx = Ox_http.Ox_http_tls_openssl.create_ctx () in
  let ssl =
    Ox_http.Ox_http_tls_openssl.create_ssl ctx ~hostname:(Some "localhost") ~ip:None
      ~alpn_protocols:[]
  in
  f ssl

let ops ssl buf ~off ~len =
  [
    ("read", fun () -> ignore (Ox_http.Ox_http_tls_openssl.read ssl buf off len));
    ("write", fun () -> ignore (Ox_http.Ox_http_tls_openssl.write ssl buf off len));
    ("bio_read", fun () -> ignore (Ox_http.Ox_http_tls_openssl.bio_read ssl buf off len));
    ("bio_write", fun () -> ignore (Ox_http.Ox_http_tls_openssl.bio_write ssl buf off len));
  ]

let test_invalid_slices_prehandshake () =
  with_prehandshake_ssl @@ fun ssl ->
  let buf = ba 8 in
  fill buf 'A';
  let reject off len =
    List.iter
      (fun (name, op) ->
        expect_invalid (Printf.sprintf "prehandshake %s off=%d len=%d" name off len) op;
        Alcotest.(check bool)
          (Printf.sprintf "prehandshake %s buffer unmodified" name)
          true (unchanged buf 'A'))
      (ops ssl buf ~off ~len)
  in
  reject (-1) 1;
  reject 0 (-1);
  reject 9 0;
  reject 8 1;
  reject 0 9;
  reject 4 5

let test_zero_length_end_slice_valid () =
  with_prehandshake_ssl @@ fun ssl ->
  let buf = ba 8 in
  fill buf 'B';
  List.iter (fun (_name, op) -> op ()) (ops ssl buf ~off:8 ~len:0);
  Alcotest.(check bool) "end slice unmodified" true (unchanged buf 'B')

let test_invalid_slices_pending_bio () =
  with_prehandshake_ssl @@ fun ssl ->
  ignore (Ox_http.Ox_http_tls_openssl.handshake ssl);
  let pending = Ox_http.Ox_http_tls_openssl.bio_write_pending ssl in
  Alcotest.(check bool) "pending BIO > 0 after handshake step" true (pending > 0);
  let decrypted = Ox_http.Ox_http_tls_openssl.ssl_pending ssl in
  let buf = ba 8 in
  fill buf 'C';
  List.iter
    (fun (name, op) ->
      expect_invalid (name ^ " pending BIO invalid slice") op;
      Alcotest.(check bool)
        (name ^ " pending BIO buffer unmodified")
        true (unchanged buf 'C');
      Alcotest.(check int)
        (name ^ " write-BIO pending unchanged")
        pending
        (Ox_http.Ox_http_tls_openssl.bio_write_pending ssl);
      Alcotest.(check int)
        (name ^ " ssl_pending unchanged")
        decrypted
        (Ox_http.Ox_http_tls_openssl.ssl_pending ssl))
    (ops ssl buf ~off:(-2) ~len:3)
