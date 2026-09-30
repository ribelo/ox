---
status: completed
package: ppx_yojson_minimal
consumer: Pie
---

# A wide defaulted record derives in linear code

## Problem Statement

Pie's Config is a plain record whose JSON codec is derived (ADR-0008): the Door decodes that record, and a missing key takes the field's default. The derived decoder copies the rest of the decoder into both the missing-key branch and the success branch of every defaulted or optional field, so the generated source grows exponentially with those fields. A wide config then does not compile: the preprocessor output is megabytes, and the compiler is killed before it finishes. Leash already hit this on its models section and kept a hand-written codec until the deriver is linear. Pie cannot use the derived codec for a record of that shape until the same defect is gone.

## Solution

Decode each record field into one local binding, in declaration order. Apply that field's default, or [None] for an option with no default, inside the binding, and continue once. The wire schema, the encoder, and the error text stay as they are.

## User Stories

1. As a service author, I want each record field decoded into one binding in declaration order, so that generated code is linear in the number of fields and a wide config compiles. ^lindec-ho00
2. As a service author, I want a missing key to apply that field's [@json.default], or [None] when an option has no default, and a present key to decode without running the default, so that defaults stay per field. ^lindec-nt5k
3. As a service author, I want a default expression to run only after earlier fields have succeeded, and not to run when an earlier field has already failed, so that a side-effecting default keeps its existing order. ^lindec-48sm
4. As a service author, I want missing-field errors, type errors, unknown-key refusal, dotted paths and redacted payloads to stay the same, and the unknown-key check to run only after every field binding has succeeded, so that existing config and request failures do not change. ^lindec-e5n0
5. As a service author, I want the encoder unchanged, including field order, omitted [None] and explicit null, so that the wire schema of a derived record stays the same. ^lindec-1szx
6. As a kernel maintainer, I want a regression that a record of about twenty defaulted fields stays under a fixed preprocessor-output bound, and that the existing fixtures still decode to the same results, so that the exponential expansion cannot return unnoticed. ^lindec-4t98

## Implementation Decisions

- The record decoder binds one field, then decodes the next. The continuation occurs once, on the success of that binding. A default or an absent option is applied inside the binding and cannot copy the rest of the decoder.
- A required field that is missing is still the missing-field error, and a present value of the wrong type is still that type error. Neither falls through to a default.
- Earlier field bindings stay in scope for a later default expression, which is where such an expression already ran.
- The unknown-key check stays after every field binding has succeeded. [[@@yojson.allow_extra_fields]] still skips it. The encoder is not modified.
- Generated identifiers keep the [ppx_yojson_] prefix. No new dependency.

## Testing Decisions

- Tests stay on the existing seam: the derived converters in [test/ppx], exercised as the public decode and encode functions, plus the preprocessor's own output for the size bound. No new test harness.
- [test/ppx/run.ml] cites lindec-e5n0 and lindec-4t98 with exact messages, paths and redaction on the fixtures already in that file; lindec-nt5k and lindec-48sm with a default that counts its evaluations; lindec-ho00 and lindec-1szx with a twenty-field record's values, unknown-key error, type error, round-trip and encoder field order. Existing encoder strings in that file keep lindec-1szx honest.
- [test/ppx/size_bound.ml] cites lindec-ho00 and lindec-4t98. It reads the driver output of a twenty-defaulted-field fixture and refuses it at 32 KB, which the duplicated form already exceeds at six defaulted fields. It also requires each field lookup once, and the unknown-key check and the record construction once each.
- A scratch copy of Leash's config, with the hand-written models codec swapped back to derived, is measured outside this tree. It is evidence, not a test of this repository.

## Out of Scope

Leash's hand-written models codec, Pie's configuration module, and any rewrite of a consumer onto the derived codec. JSON Schema derivation, polymorphic variants, and encoder changes. Installing into the shared switch, restarting services, or committing.

## Further Notes

The size bound is 32768 bytes for the twenty-field fixture. It is not a second bound on a consumer's file.

Verified: test/ppx covers ^lindec-ho00 ^lindec-nt5k ^lindec-48sm ^lindec-e5n0 ^lindec-1szx ^lindec-4t98. The twenty-field driver output is 15584 bytes. A scratch copy of Leash's config, models codec derived, is 6380318 bytes before and 72201 after; six defaulted fields of the same shape are 67557 before, already over the bound. Isolated @install, dune test, @fmt and scripts/caps-gate passed with DUNE_BUILD_DIR=_build_ppxlin. Leash, inn and grip built against a private install; nema's package built against an install from nema's Nix compiler. Not committed.
