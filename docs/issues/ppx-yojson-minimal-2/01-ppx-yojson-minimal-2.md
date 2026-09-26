---
status: completed
package: ppx_yojson_minimal
consumer: Leash (protocol and config types; the four gaps were hit writing docs/protocol.md's types in L1)
---

# Deriver, second pass: optional fields, raw JSON, wire names, empty records

## Problem Statement

Writing Leash's protocol types with `[@@deriving yojson]` hit four gaps in `ppx_yojson_minimal`: `option` fields encode as `null` instead of being omitted, so replies carry keys the protocol says are absent; there is no pass-through for a raw `Yojson.Safe.t` field, which CDP payloads and `eval` results need; constructors cannot carry a wire name, so `with_human` and friends need hand-written codecs; and an empty record cannot be derived. Each is small; together they keep the deriver from covering the shapes we own.

## Solution

Extend the deriver with the four behaviours, each opt-in by attribute where the current behaviour is defensible and default where the protocol needs it.

## User Stories

1. As a service author, I want a field of type `_ option` omitted from the object when `None` and accepted as absent or `null` when decoding, so that optional protocol fields are absent on the wire, as `docs/protocol.md` states. ^nderive-mmnx
2. As a service author, I want `[@yojson.null]` on an option field to keep the explicit-null encoding, so that a rare wire contract that needs null can have it. ^nderive-0wzg
3. As a service author, I want a field of type `Yojson.Safe.t` passed through unchanged in both directions, so that CDP payloads and `eval` values can live inside derived records. ^nderive-fpd4
4. As a service author, I want `[@name "with_human"]` on a constructor to set its wire string (a bare string for constant constructors, the tag for constructors with payload), so that variant wire names are declared on the type. ^nderive-q2om
5. As a service author, I want an empty record to derive as `{}`, so that empty arguments and replies need no special case. ^nderive-qk91
6. As a kernel maintainer, I want each behaviour pinned by a round-trip test under `test/ppx/` and the existing suites unchanged, so that the deriver's contract grows without regressing. ^nderive-l1y6

## Implementation Decisions

- Default for `option`: omit when `None` (story 1); the previous null behaviour is behind `[@yojson.null]` (story 2). Update any `eta_app` config test that depended on null.
- Variant wire names apply to both encoding and decoding; unknown tags fail with the offending subtree as today.
- OxCaml 5.4.0+ox rejects `type t = {}` at parse time. Express its one-value wire shape as `type t = unit [@@deriving yojson] [@@yojson.empty_record]`; it encodes as `{}` and decodes only `{}`, refusing unknown keys.

## Testing Decisions

- `test/ppx/`: one test per story. Leash removes its hand-written variant codecs afterwards (a Leash change, not this row).

Verified: ^nderive-mmnx ^nderive-0wzg ^nderive-fpd4 ^nderive-q2om ^nderive-qk91 ^nderive-l1y6 have round-trip and rejection coverage in `test/ppx/`; the `test/app/` config assertion now expects omitted `None`.
All three gates pass: `nix develop -c dune build @install`, `nix develop -c dune test`, `nix develop -c dune build @fmt`.

## Out of Scope

Polymorphic variants, GADTs, inline records with payload renaming, JSON Schema derivation.
