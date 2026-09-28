(lang dune 3.21)

(generate_opam_files true)

(name eta)
(authors "Rafal Krzywaznia")
(maintainers "Rafal Krzywaznia <r.krzywaznia@gmail.com>")
(license MIT)
(homepage "https://github.com/ribelo/eta")

; eta-next. Packages appear here only when a consumer's spec pulls them in.
; The compiler check survives from v1: Eta targets OxCaml exactly.
(package
 (name conf-eta-oxcaml)
 (allow_empty)
 (synopsis "Verify Eta's supported OxCaml compiler")
 (description "Checks that the selected compiler is exactly OxCaml 5.4.0+ox before compiling Eta."))

(package
 (name eta)
 (synopsis "Eta core typed failures and Eio concurrency")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eio
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_test)
 (synopsis "Eio mock test helpers and Eta Exit assertions")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eio
  eio_main
  alcotest))

; eta_json stays for unchecked JSON (CDP messages, wire shapes we do not own).
; Shapes we own are plain types with derived codecs (ADR-0008), so the packages
; that touch Yojson are eta_json, eta_observability and eta_app.
(package
 (name eta_json)
 (synopsis "Unchecked Yojson accessor and builder helpers for Eta packages")
 (description
  "eta_json provides byte-bounded Yojson parsing with a typed refusal, compact rendering, scalar and object builders, and member accessors shared by Eta packages.")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  (yojson (>= 2.0))
  (alcotest :with-test)))

(package
 (name eta_rpc)
 (synopsis "Scoped request/reply correlation over message streams")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eio
  (eta_test :with-test)
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_http)
 (synopsis "Bounded HTTP/1.1 client with verified OpenSSL TLS")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eta_json
  eio
  cstruct
  base-unix
  conf-pkg-config
  conf-openssl
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_ipc)
 (synopsis "Private Unix socket listener with scoped ownership and bounded peers")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eio
  base-unix
  (eta_test :with-test)
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_process)
 (synopsis "Scoped Unix processes with graceful termination and supervision")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eio
  base-unix
  (eta_test :with-test)
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_blocking)
 (synopsis "Bounded native calls over Eio system threads")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eio
  base-unix
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_otel)
 (synopsis "Scoped OTLP JSON logs and traces over eta_http")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eta_json
  eta_http
  eta_observability
  eio
  (eio_main :with-test)
  (alcotest :with-test)
  (yojson :with-test)))

(package
 (name eta_observability)
 (synopsis "Structured logging with fiber-local fields and journal output")
 (description
  "eta_observability writes one compact JSON object per line carrying a timestamp, a level, the service name, the message, the event's fields and the fields its fiber inherited. Secrets travel as redacted values that print as <redacted> through every path, and spans log their elapsed time and outcome without an exporter.")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eio
  eta_json
  (yojson (>= 2.0))
  mtime
  (eta_test :with-test)
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name ppx_yojson_minimal)
 (synopsis "Minimal [@@deriving yojson] preprocessor for OxCaml")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  ocaml-compiler-libs
  (yojson :with-test)
  (alcotest :with-test)))

(package
 (name eta_app)
 (synopsis "One Door for Eio services, CLI and TOML config with derived codecs")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eta_observability
  eio
  eio_main
  cmdliner
  toml
  (yojson (>= 2.0))
  (eta_test :with-test)
  (alcotest :with-test)))
(package
 (name eta_ai)
 (synopsis "Shared AI transport: bearer auth, bounded JSON POST, typed errors")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eta_json
  eta_http
  eta_observability
  eio
  (yojson (>= 2.0))
  (alcotest :with-test)))

(package
 (name eta_ai_systemone)
 (synopsis "Fail-closed System One (JEV) client over eta_http")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  ppx_yojson_minimal
  eta
  eta_ai
  eta_json
  eta_observability
  eta_http
  eio
  (yojson (>= 2.0))
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_sql_dsl)
 (synopsis "Backend-independent typed SQL DSL")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  (alcotest :with-test)))

(package
 (name eta_sql)
 (synopsis "SQLite connector, typed SQL and Eio connection pool")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta
  eta_sql_dsl
  eio
  conf-pkg-config
  conf-sqlite3
  (eio_main :with-test)
  (alcotest :with-test)))

(package
 (name eta_ai_openrouter)
 (synopsis "OpenRouter Responses, embeddings and WAV transcription")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  ppx_yojson_minimal
  eta eta_ai eta_json eta_http eta_observability eio
  (yojson (>= 2.0)) (eio_main :with-test) (alcotest :with-test)))

(package
 (name eta_ai_realtime)
 (synopsis "Scoped Codex Realtime WebSocket JSON session")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  ppx_yojson_minimal
  eta eta_ai eta_json eta_http eta_observability eio
  (yojson (>= 2.0)) (eio_main :with-test) (alcotest :with-test)))

(package
 (name eta_ai_chat)
 (synopsis "One OpenAI-compatible chat completion with a JSON-object reply")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  ppx_yojson_minimal
  eta
  eta_ai
  eta_json
  eta_observability
  eta_http
  eio
  (yojson (>= 2.0))
  (eio_main :with-test)
  (alcotest :with-test)))
