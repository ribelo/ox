---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 12: Reject known blocking operations in Eio contexts

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 11 of 19. File numbering starts after the specification.

**What to build:** Supported calls that can block the scheduler domain are reported in known Eio execution contexts, with a usable nonblocking or offloaded alternative.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-9ved, safe-r5ye, safe-ohen, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

Second direction of ox-execution-context; shares semantics with worker-context without requiring that ticket first.

## Acceptance criteria

- [ ] Identify Eio roots and callback context transfer by resolved contracts; do not infer context from file paths or assume every non-worker function runs under Eio.
- [ ] Cover a small catalogued set of synchronous waits and native calls, with worker/non-Eio controls and helper alias cases.
- [ ] For each active operation, demonstrate the sanctioned Eio or worker replacement and migrate affected supported Ox call sites.
- [ ] Record SQLite/native sites lacking a safe drop-in replacement as explicit unactivated scope with prerequisite work. Do not mark this ticket complete if its chosen active subset has no verified end-to-end case; do not claim it bans all native blocking.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-9ved: Verify known synchronous waits and blocking native operations reported in established Eio contexts; establish that one call cannot stall unrelated fibers.
- safe-r5ye: Verify operation-specific blocking facts rather than a blanket Unix ban; establish that harmless system operations and sanctioned native workers stay legal.
- safe-ohen: Verify an unavailable safe alternative to remain a named prerequisite rather than an activated prohibition; establish that the SQL native-blocking caveat is not hidden by a green policy claim.
