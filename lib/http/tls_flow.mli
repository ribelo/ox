exception Tls_failure of string

val create :
  raw:Eio.Flow.two_way_ty Eio.Resource.t ->
  ssl:Ox_http_tls_openssl.ssl ->
  Eio.Flow.two_way_ty Eio.Resource.t
