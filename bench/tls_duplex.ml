(* ^nduplex-akjv: full-duplex TLS throughput on loopback, both peers sending
   and receiving at once. Run from test/http, where the fixture certificate
   lives: dune exec bench/tls_duplex.exe -- [MiB]. *)
module H = Ox_http
module S = H.Ox_http_tls_openssl

let chunk = 16384

let pump flow total =
  let out = Cstruct.create chunk in
  let rec send left =
    if left > 0 then (
      let n = min chunk left in
      Eio.Flow.write flow [ Cstruct.sub out 0 n ];
      send (left - n))
  in
  let dst = Cstruct.create chunk in
  let rec recv left = if left > 0 then recv (left - Eio.Flow.single_read flow dst) in
  Eio.Fiber.both (fun () -> send total) (fun () -> recv total)

let report ~(caps : < Ox_caps.Cap.stdout ; .. >) ~mib ~seconds =
  Ox_caps.Cap_stdlib.printf ~caps
    "tls_duplex: %d MiB each way in %.3f s, %.1f MiB/s per direction\n" mib seconds
    (float_of_int mib /. seconds)

(* ^ncapslint-t4c6: the gate reads a benchmark like any other code. *)
let () =
  let caps = Ox_caps_door.powerbox () in
  let mib = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 64 in
  let total = mib * 1024 * 1024 in
  Eio_main.run (fun env ->
      let clock = Eio.Stdenv.mono_clock env in
      Eio.Switch.run (fun sw ->
          let listener =
            Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
          in
          let address = Eio.Net.listening_addr listener in
          let start = ref (Eio.Time.Mono.now clock) in
          Eio.Fiber.both
            (fun () ->
              let raw, _ = Eio.Net.accept ~sw listener in
              let ctx =
                S.create_server_ctx ~certificate_chain_file:"localhost.crt"
                  ~private_key_file:"localhost.key" ~alpn_protocols:[ "http/1.1" ] ()
              in
              let flow =
                H.Tls_flow.create
                  ~raw:(raw :> H.Tls_flow.ty Eio.Resource.t)
                  ~ssl:(S.create_server_ssl ctx)
              in
              pump flow total)
            (fun () ->
              let raw = Eio.Net.connect ~sw env#net address in
              let ctx = S.create_ctx () in
              S.ctx_load_ca ctx "localhost.crt";
              let ssl =
                S.create_ssl ctx ~hostname:(Some "localhost") ~ip:None
                  ~alpn_protocols:[ "http/1.1" ]
              in
              let flow =
                H.Tls_flow.create ~raw:(raw :> H.Tls_flow.ty Eio.Resource.t) ~ssl
              in
              start := Eio.Time.Mono.now clock;
              pump flow total);
          let elapsed = Mtime.span !start (Eio.Time.Mono.now clock) in
          let seconds = Mtime.Span.to_float_ns elapsed /. 1e9 in
          report ~caps:(caps :> < Ox_caps.Cap.stdout >) ~mib ~seconds))
