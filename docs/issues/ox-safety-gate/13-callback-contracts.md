---
status: done
category: enhancement
blocked_by: []
---

# Keep the committed callback repairs

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-vske

**Failure evidence:** c1b68bd (safe-vske) already moved real assertion/formatting work out of restricted callback hooks and preserved observations for the owner.

**Scope:** Retain that committed behaviour only. Do not land the uncommitted callback-contract checker, new inference, source-digest certificates, SQLite catalogue or lease fixture expansion.

**Checks:** Existing tests continue to check the committed callback observations and owner assertions. No new activation is claimed. No checker, consumer finding or activation census belongs to this runtime-only slice.
