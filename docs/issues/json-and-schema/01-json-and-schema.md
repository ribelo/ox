---
status: completed
package: eta_json, eta_schema, eta_schema_yojson
consumer: Leash milestone 1 (chrome-38a4, control protocol and config decoding in docs/protocol.md), milestone 6 (svc-ljl3)
---

# JSON and schema: copied from v1, effect-free

## Problem Statement

Leash decodes a JSON control protocol, CDP messages, and TOML config, and needs errors that say *where* a document is wrong. v1's `eta_json` (unchecked Yojson helpers) and `eta_schema` + `eta_schema_yojson` (checked decoding with JSON-pointer issue locations) do this and are effect-free, so they are copied rather than rewritten.

## Solution

Three packages copied from the v1 tag with their tests, stripped of any `Effect.t` reference, mode annotations kept only where they earn a guarantee.

## User Stories

1. As a service author, I want `Eta_json` with bounded `parse`, `to_string`, `compact`, constructors and `*_member` accessors over `Yojson.Safe.t`, so that unchecked JSON handling is one small module. ^njson-7pjx
2. As a service author, I want `Eta_json.parse` to refuse input over a byte bound with a typed error, so that a peer cannot make me allocate unboundedly. ^njson-nc66
3. As a service author, I want `Eta_schema` to describe records, variants, lists, options, strings with bounds, ints with ranges and enumerations, so that config and protocol shapes are declared once. ^njson-3vf4
4. As a service author, I want decoding to return every issue with a JSON-pointer path, so that an `invalid-request` reply or a config error names the field. ^njson-fib9
5. As a service author, I want `Eta_schema_yojson` to bridge `Yojson.Safe.t` to schema decoding and encoding, so that the wire and the schema meet in one place. ^njson-35ih
6. As a kernel maintainer, I want the v1 tests for all three packages copied and passing, so that the copy is proven equal. ^njson-3ph9
7. As a service author, I want schema-level marks for secret fields and for environment-variable overrides (`~secret:true`, `~env:"OPENROUTER_API_KEY"`), so that the Door can redact and override without a second description. ^nschema-ubrs
8. As a service author, I want an encoder direction (`to_json`) generated from the same schema, so that replies and `config check` output use the declared shape. ^nschema-59sn
9. As a service author, I want `Eta_schema` to depend on nothing but the standard library, so that it can describe wire shapes in any package. ^nschema-jcbp
10. As a kernel maintainer, I want the three packages' `docs/` stubs, `audit/` and `bench/` directories left behind in v1, so that only code and tests move. ^nschema-liiu
11. As a service author, I want decode issues to be a plain variant with a printer, so that the Door and the protocol layer can map them without string matching. ^nschema-fwsu
12. As a kernel maintainer, I want a smoke test that decodes Leash's `docs/protocol.md` example request through a schema, so that the first consumer's shape is proven on day one. ^nschema-yyfu

## Implementation Decisions

- Source: `git show v1:lib/json/…`, `v1:lib/schema/…`, `v1:lib/schema_yojson/…` and their `test/` directories. Copy, then remove every `Eta.Effect`/`Eta.Runtime` reference (there should be none in json; check schema).
- `eta_json` depends on `yojson` only; `eta_schema` on nothing; `eta_schema_yojson` on both.
- Secret/env marks are new (nschema-ubrs) and small: metadata on a field, read by `eta_app`.

## Testing Decisions

- Copied v1 tests are the regression — njson-3ph9. New tests for bounds, pointers, secret/env marks, encoder round-trip and the Leash protocol smoke — njson-nc66, njson-fib9, nschema-ubrs, nschema-59sn, nschema-yyfu.

## Out of Scope

A JSON library other than Yojson; schema-driven code generation.

## Verification

`nix develop -c dune build -p eta_json,eta_schema,eta_schema_yojson @install` is green, and `nix develop -c dune test test/json test/schema test/schema_yojson` runs 7 + 32 + 9 Alcotest cases green, every case named for the story ID it covers (`njson-7pjx`, `njson-nc66`, `njson-3vf4`, `njson-fib9`, `njson-35ih`, `njson-3ph9`, `nschema-ubrs`, `nschema-59sn`, `nschema-jcbp`, `nschema-liiu`, `nschema-fwsu`, `nschema-yyfu`); the same two gates pass in a pruned copy of the tree. The full-tree aliases ran green for this slice too; their red at hand-off is other slices' in-flight code (`lib/ipc` module `listener` has no implementation).

`nix develop -c dune build @fmt` reports no diff in any file this slice owns (its one remaining diff is `test/core/dune`, another slice); there is no `.ocamlformat` in the tree, so OCaml sources are not ocamlformat-checked, and `@doc` cannot run because `odoc` is not installed in the switch.
