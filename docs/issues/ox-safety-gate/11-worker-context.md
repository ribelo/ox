---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 11: Reject Eio operations in native worker callbacks

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 10 of 19. File numbering starts after the specification.

**What to build:** Recognised native worker callbacks cannot use operations requiring the absent Eio fiber context.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-sr6e, safe-9hbm, safe-eftp, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

First direction of ox-execution-context, independently deployable.

## Acceptance criteria

- [ ] Use resolved callback parameter roles for the blocking run variants; maintain a narrow tested catalogue of operations requiring Eio context.
- [ ] Treat nested closures according to when and where they are invoked, not lexical nesting alone. Do not execute or attribute dormant closure bodies as if called.
- [ ] Pure computation and native blocking operations remain legal in the worker; Eio-context completion hooks are clean controls.
- [ ] The installed gate distinguishes violations from unresolved helper evidence within a known worker callback; ordinary unrelated callbacks are outside scope.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-sr6e: Verify Eio suspension and context-dependent operations rejected inside callbacks passed to known blocking-worker interfaces; establish that native threads do not accidentally rely on an Eio handler.
- safe-9hbm: Verify execution of the native job distinguished from on_cancel and on_settled callbacks; establish that callbacks run in an Eio context are not misclassified as worker code.
- safe-eftp: Verify local callback aliases and helper calls analysed where evidence is available and opaque delegation disclosed; establish that passing a named function does not silently bypass the context check.
