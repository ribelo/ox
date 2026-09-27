(* Copied from v1:test/http/test_tls_handle_compare.ml, client handles. *)
module Ctx_set = Set.Make (struct
  type t = Eta_http.Eta_http_tls_openssl.ctx

  let compare = Stdlib.compare
end)

module Ssl_set = Set.Make (struct
  type t = Eta_http.Eta_http_tls_openssl.ssl

  let compare = Stdlib.compare
end)

module Session_set = Set.Make (struct
  type t = Eta_http.Eta_http_tls_openssl.session

  let compare = Stdlib.compare
end)

let check_total_order label compare a b c =
  Alcotest.(check int) (label ^ " reflexive a") 0 (compare a a);
  Alcotest.(check int) (label ^ " reflexive b") 0 (compare b b);
  Alcotest.(check int) (label ^ " reflexive c") 0 (compare c c);
  Alcotest.(check bool) (label ^ " a <> b") true (compare a b <> 0);
  Alcotest.(check bool) (label ^ " b <> c") true (compare b c <> 0);
  Alcotest.(check bool) (label ^ " a <> c") true (compare a c <> 0);
  Alcotest.(check int) (label ^ " sign reversal a b") 0 (compare a b + compare b a);
  Alcotest.(check int) (label ^ " sign reversal b c") 0 (compare b c + compare c b);
  Alcotest.(check int) (label ^ " sign reversal a c") 0 (compare a c + compare c a);
  let ordered = List.sort compare [ a; b; c ] in
  match ordered with
  | [ x; y; z ] ->
      Alcotest.(check bool)
        (label ^ " transitivity") true
        (compare x y <= 0 && compare y z <= 0 && compare x z <= 0)
  | _ -> Alcotest.fail (label ^ " expected three ordered handles")

let check_equal_implies_hash label compare hash a b =
  if compare a b = 0 then
    Alcotest.(check bool) (label ^ " equal implies hash") true (hash a = hash b)

let test_ctx_ssl_handle_ordering () =
  let ctx_a = Eta_http.Eta_http_tls_openssl.create_ctx () in
  let ctx_b = Eta_http.Eta_http_tls_openssl.create_ctx () in
  let ctx_c = Eta_http.Eta_http_tls_openssl.create_ctx () in
  check_total_order "ctx" Stdlib.compare ctx_a ctx_b ctx_c;
  check_equal_implies_hash "ctx self" Stdlib.compare Hashtbl.hash ctx_a ctx_a;
  let set =
    Ctx_set.empty |> Ctx_set.add ctx_a |> Ctx_set.add ctx_b |> Ctx_set.add ctx_c
  in
  Alcotest.(check bool) "ctx set mem a" true (Ctx_set.mem ctx_a set);
  Alcotest.(check bool) "ctx set mem b" true (Ctx_set.mem ctx_b set);
  Alcotest.(check bool) "ctx set mem c" true (Ctx_set.mem ctx_c set);
  Alcotest.(check int) "ctx set cardinal" 3 (Ctx_set.cardinal set);
  let ssl_a =
    Eta_http.Eta_http_tls_openssl.create_ssl ctx_a ~hostname:None ~ip:None
      ~alpn_protocols:[]
  in
  let ssl_b =
    Eta_http.Eta_http_tls_openssl.create_ssl ctx_a ~hostname:None ~ip:None
      ~alpn_protocols:[]
  in
  let ssl_c =
    Eta_http.Eta_http_tls_openssl.create_ssl ctx_b ~hostname:None ~ip:None
      ~alpn_protocols:[]
  in
  check_total_order "ssl" Stdlib.compare ssl_a ssl_b ssl_c;
  check_equal_implies_hash "ssl self" Stdlib.compare Hashtbl.hash ssl_a ssl_a;
  let ssl_set =
    Ssl_set.empty |> Ssl_set.add ssl_a |> Ssl_set.add ssl_b |> Ssl_set.add ssl_c
  in
  Alcotest.(check bool) "ssl set mem a" true (Ssl_set.mem ssl_a ssl_set);
  Alcotest.(check int) "ssl set cardinal" 3 (Ssl_set.cardinal ssl_set)
