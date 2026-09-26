---
status: completed
package: toolchain (shared switch and the Nix flake), dune-project
consumer: eta_app config and Leash's protocol and config types (`[@@deriving yojson]`)
---

# Make `[@@deriving yojson]` work on OxCaml 5.4.0+ox

## Problem Statement

The public OxCaml opam repository publishes `ppxlib_ast+ox` only for OCaml < 5.3, so on the 5.4.0+ox switch no ppxlib-based deriver installs, and eta-next has been writing JSON codecs by hand or through a schema DSL. That is the wrong way round: OCaml types are the schema, and deriving is how a type gets its codec. This row makes deriving work on our compiler; "not installable" is not an acceptable end state.

## Solution

Bring a ppxlib and a yojson deriver that match the switch's compiler revision (OxCaml 5.4.0-ox2) into both build paths — the shared opam switch and the hermetic Nix flake — from the OxCaml monorepo checkout at `/home/ribelo/projects/github/oxmono` (its `opam/` tree carries Jane Street's packages at the revision that tracks the compiler), or from the `oxcaml` organisation's ppxlib fork branch matching the compiler tag, or, as the last resort, a deriver written directly on the compiler's `Ast_mapper`. The row ends when a record type with `[@@deriving yojson]` round-trips in `dune test` under both paths.

## User Stories

1. As a kernel maintainer, I want `ppxlib` (with `ppxlib_ast`/`ppxlib_jane` as its OxCaml build requires) installed in the shared `5.4.0+ox` switch from sources that match the compiler revision, so that ppx-based derivers can build. ^nppx-11wi
2. As a service author, I want a yojson deriver — `ppx_yojson_conv` (Jane Street) preferred, `ppx_deriving_yojson` accepted — installed and working, so that `type t = { … } [@@deriving yojson]` yields `t_of_yojson` and `yojson_of_t` (or `of_yojson`/`to_yojson`). ^nppx-h4gz
3. As a kernel maintainer, I want the same packages resolvable in the Nix flake's hermetic build (an added opam repository input pointing at the monorepo's `opam/` tree or a vendored `vendor/opam-repository` with exactly the needed package directories), so that `nix build` is not second-class. ^nppx-tdp7
4. As a kernel maintainer, I want `eta-opam-install-ox` (row `shared-switch`) to install these toolchain packages too, idempotently, so that a consumer's shell gets them without a second command. ^nppx-hpv3
5. As a kernel maintainer, I want a test under `test/ppx/` with a record, a variant, an option, a list and a nested record deriving yojson and round-tripping, and a decode failure asserting the error carries the offending subtree, so that the deriver's contract is pinned. ^nppx-mao8
6. As a kernel maintainer, I want ADR-0007 to record the added dependencies with their source revision, and `docs/modes.md`'s Eio-gap list extended with any ppx-related gap, so that the toolchain state is written down. ^nppx-d10y
7. As a kernel maintainer, I want the route that worked and the routes that did not recorded in this spec's status, so that the next compiler bump repeats only the working one. ^nppx-oqey

## Implementation Decisions

- Routes, in order; stop at the first that works: (a) pin from `/home/ribelo/projects/github/oxmono/opam/<pkg>` at the monorepo revision whose compiler matches `ocamlc -version` = 5.4.0+ox (check its compiler pin); (b) the `oxcaml` GitHub organisation's `ppxlib` fork at the branch/tag matching 5.4.0-ox2, built with `ppxlib_jane`; (c) a minimal yojson deriver on `Ast_mapper` against the compiler's own `compiler-libs` (records, variants, options, lists, nested types; no ppxlib), owned in `lib/ppx_yojson_minimal/`.
- Do not change the compiler. Do not relax the switch invariant.
- `ocamlformat 0.29` must still pass on files using `[@@deriving]` (standard attribute syntax); if it does not, add them to `.ocamlformat-ignore` with the reason.

## Testing Decisions

- Story 5 is the test; run under both `nix develop` and `nix build`. Then run every existing suite unchanged.

## Verification (nppx-oqey)

Route (c) worked and is delivered: `lib/ppx_yojson_minimal` (text preprocessor on the compiler's own `compiler-libs`, no ppxlib) with the `ppx-yojson-minimal` binary, and `test/ppx/` with 20 tests green (`nix develop -c dune build @install`, `dune test`, `dune build @fmt` all pass; the round-trip, subtree-carrying errors and loud-failure pins hold). Route (a) failed with evidence: pinning `ppxlib` to `/home/ribelo/projects/github/oxmono/opam/ppxlib` (read as 0.39.0~5.6preview) is rejected by the solver — it requires `ocaml < 5.2.0` against the switch invariant `ocaml-variants = 5.4.0+ox`, and its `astlib` snapshots stop at 5.0.1; the pin was removed afterwards. Route (b) is unavailable as written: `github.com/oxcaml/ppxlib` does not exist, upstream `oxcaml/opam-repository` at HEAD carries the same 5.2-era stack (`ppxlib.0.33.0+ox2` capped at `ocaml < 5.3.0`, `ppx_deriving.6.1.1+ox` conflicting with `oxcaml-compiler > 5.2.0minus25`, the Jane previews conflicting with `>= 5.4.0-ox1`), upstream `ppxlib.0.38.0` is unsatisfiable against the installed guard chain, and `ppx_deriving_yojson` pulls `ppx_tools` (`ocaml < 5.1`). Story map: ^nppx-11wi is superseded by the route outcome (no ppxlib exists for this compiler and the deriver needs none); ^nppx-h4gz, ^nppx-mao8 and ^nppx-d10y are met; ^nppx-hpv3 rides the `dune-project` derivation untouched (a working-tree pin installed the package cleanly with no other switch change and was removed afterwards; the durable install happens on the next `eta-opam-install-ox` after commit); ^nppx-tdp7 needs no new repository input (`ocaml-compiler-libs` v0.17.0+ox is in the flake-pinned ox repository). The `nix build` check cannot pass until the lead commits: untracked files are invisible to the hermetic source, so `nix build .#ppx_yojson_minimal` reports the attribute missing pre-commit.

## Out of Scope

Other derivers (sexp, compare, hash) — they come with the same ppxlib once it builds and can be added by a one-line dependency when a consumer story needs them; JSON Schema generation.
