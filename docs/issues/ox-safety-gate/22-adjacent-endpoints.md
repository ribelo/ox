---
status: done
category: enhancement
package: ox_lint
consumer: Ox, Pie, Nema, Exergy
blocked_by: []
---

# Label observed ordered same-type endpoints

## User story

As an API reader, I want ordered endpoints of the same unit to have named roles,
so reversing two arguments is visible at the call site. ^safe-pwlt

## Requirements

- When adjacent unlabelled parameters have the same authenticated primitive base type and observed ordered path or interval roles, the gate shall require labels. ^safe-k6aa
- When a pair uses offset/length, quantity/unit-price, distinct semantic units or commutative operands, the gate shall not infer a swap hazard from type equality alone. ^safe-41f5
- When a seed-20261006 production sample is replayed, the probe shall reproduce forty entries and the retained manual classifications. ^safe-em3d

## Decision and acceptance

Production population 279; deterministic sample 40; 11 swap-prone (27.5%),
29 harmless. Threshold 25% met: activate a restricted observed-shape rule,
not a blanket same-type rule. Classification is semantic manual judgment,
not eleven reproduced bugs. [Forty judgments](<../../../test/lint/prevention-probes/adjacent-sample.tsv>).

Accepted shape vocabulary: src/dst, source/destination; start/stop or end_,
start_/stop or end_, start_date/end_date, start_pos/end_pos; low/high;
index/close, index/text_start; left/right only in compare_date. Base types
are compiler-expanded int, float and string (including manifest aliases).
Labelled parameters, offset/length, quantity/price and current-money/peak-money
are outside this deliberately narrow first rule. Transparent forwarding adapters
of authenticated Unix.rename/link/symlink, Sys.rename and their Cap equivalents
preserve the Stdlib ABI and are exempt
only when both positional identifiers retain their order; no source-path exemption. Aliases and lexical shadows
are checked through typed parameter identities/types, not call spelling.

## Consumer counts

Authenticated 693-source snapshot; 686 decided, 7 file unknowns, 0 visitor unknowns.

| Consumer | Decided P/T | File unknown P/T | Findings P/T |
| --- | --- | --- | --- |
| Pie | 83/99 | 2/0 | 1/0 |
| Nema | 135/73 | 0/3 | 8/3 |
| Exergy | 243/53 | 0/2 | 8/0 |

File unknowns match the [release snapshot](<21-resource-release.md>): stale Pie
build identity plus six missing annotations. Declaration-policy findings do not
assert actual swapped calls. [Replay](<../../../test/lint/prevention-probes/sample.mjs>)
reconstructs the sample from the retained population, including duplicate ordinals.
