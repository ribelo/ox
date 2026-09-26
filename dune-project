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
