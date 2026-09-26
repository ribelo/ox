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

; JSON and schema row: eta_json and eta_schema_yojson are the only packages
; that may touch Yojson; eta_schema is stdlib-only, so a schema can describe a
; wire shape in any package.
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
 (name eta_schema)
 (synopsis "Schema definitions, JSON codecs, and field marks")
 (description
  "eta_schema describes records, variants, lists, options and refined scalars; decodes and encodes JSON-shaped values with every issue carrying a JSON-pointer path; and declares secret and environment-override marks on record fields. It depends on the standard library alone.")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  (alcotest :with-test)))

(package
 (name eta_schema_yojson)
 (synopsis "Yojson adapter for eta_schema")
 (description "eta_schema_yojson binds eta_schema codecs to Yojson.Safe values.")
 (depends
  (ocaml (>= 5.4.0))
  (conf-eta-oxcaml (= :version))
  eta_schema
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
