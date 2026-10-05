---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 17: Check dynamic construction at raw SQL sinks

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 16 of 19. File numbering starts after the specification.

**What to build:** Application data reaches raw SQL as parameters rather than accidental concatenation, with explicit trusted SQL-generation seams.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-8pmk, safe-p1m1, safe-iq5u, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New ox-raw-sql-construction for supported dynamic construction reaching raw sinks.

## Acceptance criteria

- [ ] Track supported local strings from concatenation and formatting to Raw execution calls, including local aliases; known parameters supplied separately remain clean.
- [ ] Distinguish values from identifiers and schema syntax: placeholders cannot replace every SQL fragment. Dynamic identifiers require a validated structural construction interface.
- [ ] Trust only explicitly designated SQL-generation outputs, not arbitrary functions named quote or sanitize; unknown flows remain disclosed within the selected sink horizon.
- [ ] Test parameter binding with quotes and delimiter-like input through the public SQL interface, plus static migration and typed-builder controls.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-8pmk: Verify concatenation and supported formatting of dynamic values into SQL execution text reported; establish that parameter binding is not bypassed accidentally.
- safe-p1m1: Verify compiled query generation, migrations and backend-specific static SQL represented by explicit trusted contracts; establish that legitimate raw SQL remains possible without module-name exemptions.
- safe-iq5u: Verify the diagnostic to claim unparameterized construction rather than proven injection; establish that safety advice states exactly what the analysis established.
