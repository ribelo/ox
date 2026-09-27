exception Tls_failure of string

val create :
  raw:Eio.Flow.two_way_ty Eio.Resource.t ->
  ssl:Eta_http_tls_openssl.ssl ->
  Eio.Flow.two_way_ty Eio.Resource.t
