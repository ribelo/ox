---
status: done
category: enhancement
package: ox_lint
consumer: Ox, Pie, Nema, Exergy
blocked_by: []
---

# Establish resource release paths

## User story

As a daemon maintainer, I want raw acquisitions to have an explicit local release
path, so exceptional validation cannot silently leak resources. ^safe-cank

## Requirements

- When an authenticated Cap_unix openfile*, open_process*, socket or pipe acquisition reaches no local release path, the gate shall report the acquisition. ^safe-763t
- When a release callback closes a different resource, the gate shall not treat it as cleanup of the acquired resource. ^safe-mzdt
- When local aliases, tuple endpoints or scoped acquisition/release callbacks identify the same handle, the gate shall preserve that identity. ^safe-f1yz

## Acceptance and boundary

Structured paths: Switch.on_release, Resource.use_in_scope,
use_closeable_in_scope and Fun.protect ~finally. Equivalent local exception
cleanup is accepted, including a resolved local guard helper. Imported helpers
are not proof. This is a structural policy, not a demonstrated runtime leak.
Returned caller-owned handles may be policy findings, not asserted leaks.
Cap_unix.pipe is absent from the current API; its identity is conditional on
availability, not approximated by raw Unix.pipe spelling. Tuple components are
checked individually. Mutable-reference alias evidence is local and conservative.

## Consumer counts

Authenticated 693-source snapshot; 686 decided, 7 file unknowns, 0 visitor unknowns.

| Consumer | Decided P/T | File unknown P/T | Findings P/T |
| --- | --- | --- | --- |
| Pie | 83/99 | 2/0 | 4/10 |
| Nema | 135/73 | 0/3 | 7/4 |
| Exergy | 243/53 | 0/2 | 0/0 |

File unknowns: Pie generated build identity has stale digest; skill_cli interface
has no annotation; three isolated Nema Ladybug identity controls and two Exergy
tests lack annotations. Findings are local-policy gaps, including intentional
transfers/manual lifetimes, not eleven established production leaks.

The concrete [Pie history gap](</home/ribelo/projects/ribelo/pie/docs/issues/history-release-path/01-history-release-path.md>) is docs-only.
