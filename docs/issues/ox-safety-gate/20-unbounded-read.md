---
status: done
category: enhancement
package: ox_lint
consumer: Ox, Pie, Nema, Exergy
blocked_by: []
---

# Bound whole-stream acquisition

## User story

As a daemon maintainer, I want whole-output and body acquisition to carry a finite
budget, so an external producer cannot exhaust memory silently. ^safe-sx2y

## Requirements

- When an authenticated whole-stream sink has no finite local budget, the gate shall report its location. ^safe-5ajg
- When compiler identity or reader ownership cannot be resolved, the gate shall report undecided evidence rather than infer a defect from spelling. ^safe-88rt
- When the budget is explicit and finite, the gate shall accept the read, including aliased producers. ^safe-qczi

## Acceptance and boundary

One clean and one violating fixture cover finite max_size, module/value aliases,
shadowing, raw read_all, parse_out/take_all, and explicit max_int.
of_flow's required label is already a type guarantee. Ox HTTP's bounded defaults
and Byte_limit API are not raw sinks. Imported helper bodies are not analysed.

## Consumer run — 2026-10-06

Counts P/T; newly built visitor, existing authenticated compiler artifacts, 693 sources.

| Consumer | Decided | File unknown | Findings | Visitor unknown |
|---|---:|---:|---:|---:|
| Pie | 84/99 | 1/0 | 3/3 | 0/0 |
| Nema | 135/73 | 0/3 | 0/0 | 0/0 |
| Exergy | 243/51 | 0/4 | 0/0 | 0/0 |

Production findings: [sh:67](</home/ribelo/projects/ribelo/pie/packages/pie/sh.ml#L67>),
[audio_archive:200](</home/ribelo/projects/ribelo/pie/packages/pie/recording/audio_archive.ml#L200>)
and [278](</home/ribelo/projects/ribelo/pie/packages/pie/recording/audio_archive.ml#L278>).
They are unbounded subprocess captures, not memory-exhaustion reproductions.
Eight missing annotations remain disclosed, not counted clean. One docs-only Pie
issue groups the three production risks; no consumer implementation change.
