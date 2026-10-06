---
status: done
category: bug
package: ox_lint
consumer: Exergy, Ox, Pie, Nema
blocked_by: []
---

# Decide Stdlib contracts and workspace package bodies

## User story

As an Exergy maintainer, I want the gate to distinguish total Stdlib bodies from
raising callbacks, so ordinary projections do not make my public contract undecidable.

## Requirements

- When a call resolves through compiler paths to a finite total Stdlib contract, the gate shall decide that body's suspension and raising effects, including through aliases. ^nlintd-7x5n
- When a finite Stdlib combinator invokes a callback, the gate shall retain the callback's suspension, cancellation and exception effects, including partial applications and surrounding handlers. ^nlintd-b362
- When comparison may reach a function, a called value is shadowed, an operation is outside the finite table, or a returned function is invoked without body evidence, the gate shall report a reachable defect or undecided evidence rather than accept a total-body claim. ^nlintd-2tmh

- When a public value is exported through a compiler-resolved module alias or include, or calls another library in the same workspace, the gate shall locate the callee CMT through its authenticated imported-CMI path, validate its interface fingerprint and authored source, and use its implementation binding; it shall report opacity only when annotation evidence is unavailable or its body contains unresolved operations. ^nlintd-k036

## Acceptance

Clean and violating typed fixtures cover fst/snd, List.length, Fun.id, Result
map/map_error/bind/is_ok and Syntax, and Option some/value/join/is_none/is_some/
to_result/to_list/map/bind/fold/iter/equal/compare. Scalar equality is safe;
lists compared with the empty constructor cannot visit any element, including
polymorphic or functional elements. Non-empty functional comparison remains opaque.
Alias/include fixtures prove clean bodies and retain suspension, cancellation and
exception effects from violating bodies. The cross-library variant is the second
commit of this slice. Imported implementations
are loaded on demand in the same workspace build context, including Dune public-CMI
to byte-CMT layouts. Each public proof preserves its documented delegated boundaries
and restores its own compiler environment before cancellation cleanup analysis.
Authenticated, bounded scalar Printf format ASTs are total; dynamic widths, strings,
substitutions and callback formatting remain outside that finite contract.
Function equality and Option.get remain outside the non-raising table.
No exemption is based on call spelling. Exergy's motivating signatures are
[the adjusted-candle entry points](</home/ribelo/projects/exergy/lib/ingest/ingest.mli#L900-L948>).

No Exergy source or documentation changes are part of the fix.
Each commit requires all four Ox gates. Full acceptance additionally requires zero
undecided results on Exergy lib/bin. Both motivating Ingest public values are
now decided by the verified cross-library slice.
Retain same-artifact Exergy, Pie and Nema before/after counts here; full-rule consumer
totals are distinct from the architect's focused public-contract counts.

## Verified delivery

The finite Stdlib and alias/include slice landed as
`be3df2531d1662caff1368799dadc4d709d93048`, with all four serial Ox gates green.
The second slice authenticates on-demand workspace imports against their CMI
fingerprints and authored sources, including public-CMI/byte-CMT layouts.

The remaining Ingest opacity was not a failed `Vocab.Interval.to_string` lookup.
Its reachable `Ingest_assets_quotes` body delegates through an opaque observability
span. A clause-scoped proof now recognizes a named authenticated reachable callee
only when its substituted, filtered effects contribute to the current opacity.
Total callees, unrelated opacity and the canonical exported caller
(including its local helpers and synthetic application nodes) cannot witness
delegation. This qualifies only the authored current-val clause; it does not
manufacture an exception summary for callers. Positive and negative typed
regressions cover these cases.

### Matched consumer measurements

Explicit `--repo-gate --require-typed` scans used the pre-Stdlib checker and the
new checker on the same available consumer evidence, with no consumer rebuild
or source/documentation workaround by this slice. These are all-rule totals,
not focused documentation-contract counts. Every scan reported zero rebuilt
workspaces.

| Consumer and scope | Before findings / undecided modules | After findings / undecided modules | Checker exit before / after |
| --- | --- | --- | --- |
| Exergy `lib bin` | 0 / 1 | 0 / 0 | 2 / 0 |
| Pie `packages/pie` | 0 / 24 | 0 / 24 | 2 / 2 |
| Nema `lib bin` | 22 / 3 | 22 / 3 | 2 / 2 |

The final engine also passed Exergy at `de7ffd4`: zero findings and zero undecided
modules, after its independent identity-only commit, with runtime sources
unchanged. Pie retains stale generated `build_identity` evidence and missing
executable annotations; this measurement does not re-establish the historical
focused seven-to-zero result. Nema retains missing annotations for three
`ladybug_identity_components` test modules. Neither matched comparison increased
findings or undecided counts.

Both slices passed `dune build @install`, `dune test`, `dune build @fmt` and
`scripts/caps-gate` in that serial order. The final staged inventory includes
the new helper libraries; the aggregate safety-gate delivery row remains open
for its other work.
