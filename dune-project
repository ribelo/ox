(lang dune 3.21)

(generate_opam_files true)

(name ox)
(authors "Rafal Krzywaznia")
(maintainers "Rafal Krzywaznia <r.krzywaznia@gmail.com>")
(license MIT)
(homepage "https://github.com/ribelo/ox")

; ox. A package appears here when a spec story needs it (AGENTS.md: Ox is its own consumer).
; The compiler check survives from v1: Ox targets OxCaml exactly.
(package
 (name conf-ox-oxcaml)
 (allow_empty)
 (synopsis "Verify Ox's supported OxCaml compiler")
 (description "Checks that the selected compiler is exactly OxCaml 5.4.0+ox before compiling Ox."))

(package
 (name ox)
 (synopsis "Ox core typed failures and Eio concurrency")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  (eio (>= 1.6))
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

; ^ncaps-sojd ^ncaps-4btv ^ncaps-n6r0: capability types, the wrappers of the dangerous
; standard-library calls, and the Semgrep rules and gate script (installed under
; share/ox_caps). No dependency beyond the standard library and unix; docs/caps.md.
(package
 (name ox_caps)
 (synopsis "Capabilities in signatures: typed wrappers of dangerous stdlib calls and their Semgrep gate")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  base-unix))

(package
 (name ox_test)
 (synopsis "Eio mock test helpers and Ox Exit assertions")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_caps
  (eio (>= 1.6))
  (eio_main (>= 1.6))
  alcotest))

; ox_json stays for unchecked JSON (CDP messages, wire shapes we do not own).
; Shapes we own are plain types with derived codecs (ADR-0008), so the packages
; that touch Yojson are ox_json, ox_observability and ox_app.
(package
 (name ox_json)
 (synopsis "Unchecked Yojson accessor and builder helpers for Ox packages")
 (description
  "ox_json provides byte-bounded Yojson parsing with a typed refusal, compact rendering, scalar and object builders, and member accessors shared by Ox packages.")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  (yojson (>= 2.0))
  (alcotest :with-test)))

(package
 (name ox_rpc)
 (synopsis "Scoped request/reply correlation over message streams")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  (eio (>= 1.6))
  (ox_test :with-test)
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_http)
 (synopsis "Bounded HTTP/1.1 client with verified OpenSSL TLS")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_json
  (eio (>= 1.6))
  cstruct
  base-unix
  conf-pkg-config
  conf-openssl
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_ipc)
 (synopsis "Private Unix socket listener with scoped ownership and bounded peers")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_caps
  (eio (>= 1.6))
  base-unix
  (ox_test :with-test)
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_process)
 (synopsis "Scoped Unix processes with graceful termination and supervision")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_caps
  (eio (>= 1.6))
  base-unix
  (ox_test :with-test)
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_blocking)
 (synopsis "Bounded native calls over Eio system threads")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  (eio (>= 1.6))
  base-unix
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_otel)
 (synopsis "Scoped OTLP JSON logs and traces over ox_http")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_json
  ox_http
  ox_observability
  ox_caps
  (eio (>= 1.6))
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)
  (yojson :with-test)))

(package
 (name ox_observability)
 (synopsis "Structured logging with fiber-local fields and journal output")
 (description
  "ox_observability writes one compact JSON object per line carrying a timestamp, a level, the service name, the message, the event's fields and the fields its fiber inherited. Secrets travel as redacted values that print as <redacted> through every path, and spans log their elapsed time and outcome without an exporter.")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  (eio (>= 1.6))
  ox_json
  (yojson (>= 2.0))
  mtime
  (ox_test :with-test)
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ppx_yojson_minimal)
 (synopsis "Minimal [@@deriving yojson] preprocessor for OxCaml")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ocaml-compiler-libs
  (yojson :with-test)
  (alcotest :with-test)))

(package
 (name ox_app)
 (synopsis "One Door for Eio services, CLI and TOML config with derived codecs")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_caps
  ox_observability
  (eio (>= 1.6))
  (eio_main (>= 1.6))
  cmdliner
  toml
  (yojson (>= 2.0))
  (ox_test :with-test)
  (alcotest :with-test)))
(package
 (name ox_ai)
 (synopsis "Shared AI transport: bearer auth, bounded JSON POST, typed errors")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_json
  ox_http
  ox_observability
  (eio (>= 1.6))
  (yojson (>= 2.0))
  (alcotest :with-test)))

(package
 (name ox_ai_systemone)
 (synopsis "Fail-closed System One (JEV) client over ox_http")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ppx_yojson_minimal
  ox
  ox_ai
  ox_json
  ox_observability
  ox_http
  (eio (>= 1.6))
  (yojson (>= 2.0))
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_sql_dsl)
 (synopsis "Backend-independent typed SQL DSL")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  (alcotest :with-test)))

(package
 (name ox_sql)
 (synopsis "SQLite connector, typed SQL and Eio connection pool")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ox
  ox_caps
  ox_sql_dsl
  (eio (>= 1.6))
  conf-pkg-config
  conf-sqlite3
  (ox_test :with-test)
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))

(package
 (name ox_ai_openrouter)
 (synopsis "OpenRouter Responses, embeddings and WAV transcription")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ppx_yojson_minimal
  ox ox_ai ox_json ox_http ox_observability (eio (>= 1.6))
  (yojson (>= 2.0)) (eio_main (and :with-test (>= 1.6))) (alcotest :with-test)))

(package
 (name ox_ai_realtime)
 (synopsis "Scoped Codex Realtime WebSocket JSON session")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ppx_yojson_minimal
  ox ox_ai ox_json ox_http ox_observability (eio (>= 1.6))
  (yojson (>= 2.0)) (eio_main (and :with-test (>= 1.6))) (alcotest :with-test)))

(package
 (name ox_ai_chat)
 (synopsis "One OpenAI-compatible chat completion with a JSON-object reply")
 (depends
  (ocaml (>= 5.4.0))
  (conf-ox-oxcaml (= :version))
  ppx_yojson_minimal
  ox
  ox_ai
  ox_json
  ox_observability
  ox_http
  (eio (>= 1.6))
  (yojson (>= 2.0))
  (eio_main (and :with-test (>= 1.6)))
  (alcotest :with-test)))
