---
status: in-progress
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
undecided results on Exergy lib/bin; the two Ingest public values remain pending
until the cross-library commit is verified.
Retain same-artifact Exergy, Pie and Nema before/after counts here; full-rule consumer
totals are distinct from the architect's focused public-contract counts.
