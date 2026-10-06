---
status: done
category: enhancement
blocked_by: []
---

# Restore legacy discarded-result semantics

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-s6km, safe-prune

**Failure evidence:** 2908f217 (2026-10-04) accepted deliberate named discards and result conversions; the later extension produced 33 production findings and zero defects in the architect audit.

**Scope:** Keep the original bare ignore/wildcard failure check. Accept commented named best-effort bindings and result-to-option/unit matches. Remove the new local allowance interpreter; do not change evaluation or failure behaviour.

**Checks:** Pin the historical clean/violating boundary and one named release plus result-to-option consumer control. The active historical rule is restored in f1c4f127; no new rule or activation decision remains.
