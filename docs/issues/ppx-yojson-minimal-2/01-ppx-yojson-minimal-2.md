---
status: done
package: ppx_yojson_minimal
consumer: Exergy domain encoders and existing native JSON users
priority: P2
---

# Native JSON deriver: one-way and module-local extension decision

## Problem Statement

Exergy contains 206 implementation deriving annotations, 182 encoder-only, and 217 interface annotations, 196 encoder-only. Several live inside ordinary nested modules; two interface requests encode abstract types. The native deriver currently recognizes bidirectional yojson only and deliberately rejects nested derivation. Four derived implementation declarations also use inline-record constructors. These are real syntax mismatches, but they do not authorize copying a legacy JSON wire convention or synthesizing invariant-bypassing decoders. Hand-owned Exergy codecs remain a valid migration route.

## Solution

Extend Ox with native encoder-only and ordinary module-local derivation while retaining the delivered native contract. Exergy owns its public wire compatibility; this is not a legacy-PPX compatibility layer. Inline-record constructors remain unsupported and must be refactored or hand-encoded by Exergy.

## User Stories

1. As a service author, I want a field of type `_ option` omitted from the object when `None` and accepted as absent or `null` when decoding, so that optional protocol fields are absent on the wire, as `docs/protocol.md` states. ^nderive-mmnx
2. As a service author, I want `[@yojson.null]` on an option field to keep the explicit-null encoding, so that a rare wire contract that needs null can have it. ^nderive-0wzg
3. As a service author, I want a field of type `Yojson.Safe.t` passed through unchanged in both directions, so that CDP payloads and `eval` values can live inside derived records. ^nderive-fpd4
4. As a service author, I want `[@name "with_human"]` on a constructor to set its wire string (a bare string for constant constructors, the tag for constructors with payload), so that variant wire names are declared on the type. ^nderive-q2om
5. As a service author, I want an empty record to derive as `{}`, so that empty arguments and replies need no special case. ^nderive-qk91
6. As a kernel maintainer, I want each behaviour pinned by a round-trip test under `test/ppx/` and the existing suites unchanged, so that the deriver's contract grows without regressing. ^nderive-l1y6
7. As a service author, I want `Eta_json.Of_json` decoder combinators — `field`, `at`, `list`, `option`, `one_of`, `try_or_none`, primitives — where a decoder is `Yojson.Safe.t -> ('a, issue) result` carrying the path of the failure, so that dynamic JSON (CDP payloads) is read by composing functions rather than nesting `member` calls. ^nderive-vq4n
8. As a kernel maintainer, I want the deriver's attributes named as jsonkit's (`[@json.default e]`, `[@json.key "name"]`, `[@json.name "tag"]` on constructors, `[@json.null]` for explicit null), so that a later switch to jsonkit's ppx and its JSON Schema derivation is mechanical. ^nderive-ze85
9. As a domain author, I want encoder-only derivation for supported native types without any generated decoder, so that serialization does not open an unauthorized construction path. ^nderive-s2lt
10. As a domain author, I want encoder-only generation to depend only on constituent encoders, so that records containing invariant-bearing types with no decoder still compile. ^nderive-u3ux
11. As a library author, I want an abstract type in an encoder-only interface declaration to produce an encoder signature only, so that its concrete or manual implementation can remain private. ^nderive-9atb
12. As a library author, I want supported encoder-only implementation and interface declarations to agree, so that generated names and types are checked by the compiler. ^nderive-07js
13. As a domain author, I want derivation in ordinary nested module structures and signatures to emit converters inside the declaring module, so that Money.t and Prediction.t keep their real namespace. ^nderive-i3v2
14. As a library author, I want identical type names in sibling modules to have distinct correctly scoped converters, so that module-local generation cannot collide at the outer level. ^nderive-sfta
15. As a library author, I want local and module-qualified converter references to work within nested derivation without adding unavailable decoder dependencies, so that nested native types compose. ^nderive-cd80
16. As a wire-contract author, I want supported native shapes to keep their existing nullary strings, tagged payloads, option omission, attributes and result-returning decode semantics, so that an extension does not silently imitate a retired deriver. ^nderive-p4tq
17. As a library author, I want supported bidirectional derivation to work module-locally without altering top-level or recursive behavior, so that traversal is a native syntax extension rather than an encoder-only special case. ^nderive-ufnu
18. As a test author, I want compiled positive/negative implementation-interface fixtures and golden JSON plus source-location assertions, so that generated-module ownership and useful compiler diagnostics are acceptance properties. ^nderive-e5va

## Implementation Decisions

- Existing delivered native attributes and codecs remain authoritative: nullary constructors are strings, ordinary payload constructors are tagged arrays, None fields are omitted unless explicitly marked, and decoders return results. Never change these defaults to conv conventions.
- Encoder-only mode generates no decoder binding, decoder signature or constituent decoder dependency. An abstract interface may declare its encoder; an abstract implementation still cannot invent a representation.
- Ordinary nested module traversal places generated converters in the declaring structure/signature and preserves namespace, source ordering and locations. Module-local support does not imply support for arbitrary functors, local first-class modules, GADTs or private representations.
- Preserve existing monomorphic recursive/mutually recursive derivation and raw JSON/attribute support. Exergy does not request parameterized, polymorphic-variant or private-type derivation.
- Keep native generation lightweight and OxCaml-compatible; no ppxlib/conv fallback, runtime dispatch by old annotation or automatic compatibility codecs.

## Testing Decisions

- Confirmed seam: actual compile fixtures plus golden wire JSON. String inspection of generator output alone does not prove interface/module correctness. Run on the supported OxCaml compiler.
- Encoder-only fixtures must compile with constituent encoders but no constituent decoders. A compile-negative consumer must be unable to reference a generated decoder. Pair concrete implementation and abstract encoder interface, plus a manual implementation behind that interface.
- Test M.t and N.t in sibling modules, nested module-qualified references, matching implementation/interface declarations, and bidirectional nested supported types. Preserve existing top-level, recursive and native attribute fixtures.
- Compile-error fixtures assert useful filename/line attribution inside generated module-local code and unchanged source line attribution afterward; unsupported shapes still fail rather than partially generating silently.
- Inline-record constructors are rejected in both modes and both implementations/signatures. No wire representation is inferred from a conv snapshot.

## Out of Scope

Legacy ppx_yojson_conv compatibility, throwing-decoder defaults, deriving decoders for invariant-bearing private types, invented abstract implementations, unrelated parameterized/polymorphic-variant/GADT support, JSON Schema, and automatic changes to Exergy public JSON. Inline-record support remains unsupported.

## Further Notes

### Decisions required — resolved 2026-10-04

1. Native encoder-only (`[@@deriving yojson_of]`) and ordinary module-local derivation enter Ox as native extensions.
2. Inline-record constructors remain unsupported, with a clear rejection. Exergy will refactor its four occurrences or hand-write codecs; no inline-record JSON representation is added.
3. Exergy owns its public wire compatibility and corresponding requirements/fixtures. Ox preserves its native defaults and does not imitate ppx_yojson_conv conventions.

### Evidence and already-covered shapes

- Audit 2026-10-04 at Ox `08c6fc8f`, unchanged relevant source at `72af4cde`. Original eight story IDs retain historical delivery. At audit time, the extension decisions were unresolved and no new generated-code compile tests had been executed.
- Delivered native boundaries: [mode parser:50–61](<../../../lib/ppx_yojson_minimal/derive.ml#L50-L61>), [encoder/optional-decoder generation:611–693](<../../../lib/ppx_yojson_minimal/derive.ml#L611-L693>), [signature generation:695–714](<../../../lib/ppx_yojson_minimal/derive.ml#L695-L714>), [module-local traversal:812–932](<../../../lib/ppx_yojson_minimal/derive.ml#L812-L932>), and [documented native contract:20–76](<../../../lib/ppx_yojson_minimal/derive.mli#L20-L76>).
- Consumer evidence: [Money implementation:529–538](</home/ribelo/projects/exergy/lib/vocab/vocab.ml#L529-L538>), [Money interface:72–78](</home/ribelo/projects/exergy/lib/vocab/vocab.mli#L72-L78>), [portfolio encoders:24–39](</home/ribelo/projects/exergy/lib/quant/portfolio_mechanics.ml#L24-L39>), [prediction encoder:2246–2254](</home/ribelo/projects/exergy/lib/vocab/vocab.ml#L2246-L2254>), and [handwritten Data_source encoder:543](</home/ribelo/projects/exergy/lib/quant/data_source.ml#L543>).
- Complete derived inline-record census: [corporate_action:43–55](</home/ribelo/projects/exergy/lib/quant/data_source.ml#L43-L55>), [deexposure:5–19](</home/ribelo/projects/exergy/lib/quant/redp_portfolio.ml#L5-L19>), [Strategy.Redp re-export:88–102](</home/ribelo/projects/exergy/lib/quant/strategy.ml#L88-L102>), and [citrini_index_asset_source:74–82](</home/ribelo/projects/exergy/lib/ingest/ingest_assets.ml#L74-L82>); each has a corresponding interface declaration.
- Already supported: ordinary records/variants/aliases/options/lists/arrays/tuples, raw JSON, supported native attributes, qualified codecs, recursive and mutually recursive monomorphic types. Exergy has no derived declaration requiring type parameters, polymorphic variants, private types or mutually recursive groups. These are not new prerequisites.
- Existing [shape rejection/interface fixtures:549–598](<../../../test/ppx/run.ml#L549-L598>) retain unsupported-shape checks; the former ordinary-module rejection is replaced by [compiled extension fixtures](<../../../test/ppx/extensions.ml>). [Generated-code location directives:1010–1042](<../../../lib/ppx_yojson_minimal/derive.ml#L1010-L1042>) are checked by [real compiler filename/line fixtures](<../../../test/ppx/compile/check.sh#L62-L77>).
- Existing attributes use jsonkit-style naming; its ppxlib-based implementation was previously unavailable on this compiler. Replacing the generator or adopting jsonkit remains an independent ADR/dependency decision, not this audit's recommendation.

Verified 2026-10-04: `nix develop -c dune test test/ppx --force` passed [run.ml](<../../../test/ppx/run.ml>) (33 tests), [extensions.ml](<../../../test/ppx/extensions.ml>) (4 tests), [size_bound.ml](<../../../test/ppx/size_bound.ml>) and [compile/check.sh](<../../../test/ppx/compile/check.sh>) (5 controls, 16 negative compiler fixtures; module-local encoder/decoder and restored-line attribution).
Slice formatting and the required `nix develop -c dune build @install` passed. Repository `dune test` and `@fmt` exited 1 on concurrent lint/deployment evidence and unrelated formatting; `caps-gate` exited 2 with zero findings and stale typed evidence for the unrelated benchmark and ox_lint main module.

