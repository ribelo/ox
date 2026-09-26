---
status: completed
package: eta_json (eta_schema and eta_schema_yojson were removed by row 16)
consumer: Leash milestone 1 (chrome-38a4; the protocol and config types are derived in Leash itself), milestone 6 (svc-ljl3)
---

# JSON and schema: copied from v1, effect-free

## Problem Statement

Leash decodes a JSON control protocol, CDP messages, and TOML config. CDP messages are JSON whose shape belongs to Chrome, so they need unchecked access with bounded parsing; the protocol and config shapes are ours, and since ADR-0008 they are plain OCaml types with derived codecs. v1 answered both with a schema combinator library, which restated every type as a value and is gone (row 16, `docs/issues/remove-eta-schema/01-remove-eta-schema.md`).

## Solution

`eta_json` — copied from the v1 tag with its tests, stripped of any `Effect.t` reference, mode annotations kept only where they earn a guarantee — remains for unchecked JSON. `eta_schema` and `eta_schema_yojson` were delivered by row 3 and deleted by row 16; nothing here describes a schema value any more.

## User Stories

1. As a service author, I want `Eta_json` with bounded `parse`, `to_string`, `compact`, constructors and `*_member` accessors over `Yojson.Safe.t`, so that unchecked JSON handling is one small module. ^njson-7pjx
2. As a service author, I want `Eta_json.parse` to refuse input over a byte bound with a typed error, so that a peer cannot make me allocate unboundedly. ^njson-nc66
3. As a service author, I want `Eta_schema` to describe records, variants, lists, options, strings with bounds, ints with ranges and enumerations, so that config and protocol shapes are declared once. Superseded by ADR-0008 and ^nnoschema-ttb5: the type is the schema and the deriver is the codec. ^njson-3vf4
4. As a service author, I want decoding to return every issue with a JSON-pointer path, so that an `invalid-request` reply or a config error names the field. Superseded by ^nnoschema-zi2m: the deriver's message names a dotted path and carries the offending subtree (or the unknown key), and an object field the type does not name is refused rather than dropped, so an unknown request argument still answers `invalid-request`. ^njson-fib9
5. As a service author, I want `Eta_schema_yojson` to bridge `Yojson.Safe.t` to schema decoding and encoding, so that the wire and the schema meet in one place. Superseded by ^nnoschema-ttb5: the derived converters are the bridge. ^njson-35ih
6. As a kernel maintainer, I want the v1 tests for all three packages copied and passing, so that the copy is proven equal. Superseded in part by ^nnoschema-ttb5: `eta_json`'s v1 tests stand in `test/json/`; the schema packages' tests went with the packages. ^njson-3ph9
7. As a service author, I want schema-level marks for secret fields and for environment-variable overrides (`~secret:true`, `~env:"OPENROUTER_API_KEY"`), so that the Door can redact and override without a second description. Superseded by ^nnoschema-ifg0 (a secret is `Eta_observability.Redact.t`, so it is redacted by type) and ^nnoschema-5mdj (overrides are an explicit function over the decoded config). ^nschema-ubrs
8. As a service author, I want an encoder direction (`to_json`) generated from the same schema, so that replies and `config check` output use the declared shape. Superseded by ^nnoschema-5mdj and ^nnoschema-36cj: the derived `yojson_of_t` is the encoder, and `config check` prints it. ^nschema-59sn
9. As a service author, I want `Eta_schema` to depend on nothing but the standard library, so that it can describe wire shapes in any package. Superseded by ^nnoschema-ttb5: the package is gone; a derived codec needs `yojson` and the preprocessor only. ^nschema-jcbp
10. As a kernel maintainer, I want the three packages' `docs/` stubs, `audit/` and `bench/` directories left behind in v1, so that only code and tests move. Superseded by ^nnoschema-ttb5 for the two schema packages; `eta_json` moved without them. ^nschema-liiu
11. As a service author, I want decode issues to be a plain variant with a printer, so that the Door and the protocol layer can map them without string matching. Superseded by ^nnoschema-zi2m: the deriver reports one string, which `invalid-request` and the Door print unchanged. ^nschema-fwsu
12. As a kernel maintainer, I want a smoke test that decodes Leash's `docs/protocol.md` example request, so that the first consumer's shape is proven on day one. Superseded by ^nnoschema-44wj: it is a derived-type round-trip in `test/json/`, not a schema. ^nschema-yyfu
13. As a kernel maintainer, I want `eta_json` to stay after the schema packages are gone, for JSON whose shape belongs to a peer, so that CDP messages stay unchecked while the shapes we own derive their codecs. Supersedes the schema half of ^njson-3vf4. ^njson-cdp0

## Implementation Decisions

- Source: `git show v1:lib/json/…` and its `test/` directory (`lib/schema/`, `lib/schema_yojson/` and their tests were deleted in row 16).
- `eta_json` depends on `yojson` only, and is the one Eta package whose types are the peer's, not ours.
- Leash's example request is decoded by a plain record type with `[@@deriving yojson]` in `test/json/`: the same bytes, the same field names, no schema value to keep in step.

## Testing Decisions

- `eta_json`'s copied v1 tests are the regression — njson-3ph9. New tests for the byte bound and the accessors — njson-nc66, njson-7pjx.
- The Leash protocol example is a derived-type round-trip, with a decode failure naming the nested path and carrying the offending subtree, and a CDP-shaped document round-tripping unchecked through `Eta_json` beside it — ^nnoschema-44wj, ^nnoschema-zi2m, ^njson-cdp0.

## Out of Scope

A JSON library other than Yojson; schema-driven code generation; JSON Schema generation for AI tool definitions (its own row when the AI package is pulled).

## Verification

`nix develop -c dune build @install`, `dune test` and `dune build @fmt` passed for the whole tree after row 16; `dune test test/json` runs 8 cases green, the seven `eta_json` cases plus the derived Leash protocol round-trip (`^nnoschema-44wj`, `^nnoschema-zi2m`).
The two removed packages are gone from `dune-project`, the flake's derived package list, `README.md` and the tree; the grep for `Eta_schema` finds history under `docs/issues/` and ADR-0008 only.
