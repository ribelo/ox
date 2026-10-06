---
status: done
category: enhancement
package: ox_lint
consumer: Ox, Pie, Exergy, Nema
blocked_by: []
---

# Catch concrete Eio and Ox defects

## Problem statement

Agents produce transaction escapes, fiber-blocking calls, Eio calls on native workers, wall-clock elapsed arithmetic, cancellation masks around indefinite work, and dynamic SQL text. The gate must catch those failures, not import a catalogue of language style rules. The architect reduced this delivery on 2026-10-06 after the real consumer audit found no defects in the rejected ports.

## Stories

1. As the architect, I want the unsupported ports, their tests, fixtures, documentation and tickets removed, so that the gate pays only for concrete failures. ^safe-prune
2. As a maintainer, I want named best-effort discards with explanatory comments and explicit result-to-option/unit conversions accepted, so that deliberate recovery needs no allowance attribute. Bare ignored failures retain the earlier check. ^safe-s6km
3. As a native adapter author, I want Eio operations rejected in callbacks actually executed by Ox_blocking, so that native threads do not require an absent fiber handler. ^safe-sr6e
4. As a maintainer, I want Eio-context completion hooks and dormant worker partial applications kept distinct from native execution, so that the rule reports the executed callback, not lexical nesting. ^safe-9hbm
5. As an agent, I want local worker aliases/helpers followed and relevant unavailable evidence reported, so that optional defaults cannot silently hide Eio work. ^safe-eftp
6. As a Service author, I want known blocking waits in Eio contexts reported, so that one fiber cannot stall its siblings. ^safe-9ved
7. As a maintainer, I want operation-specific sleep, joins and semaphore waits checked rather than a blanket Unix ban, so that harmless system calls and native jobs remain legal. Stdlib locks stay with the existing lock rule. ^safe-r5ye
8. As a reviewer, I want unsupported blocking alternatives disclosed before activation, so that a prohibition does not hide a missing safe implementation. ^safe-ohen
9. As a maintainer, I want the callback fixes already committed as c1b68bd retained without extending the callback checker, so that this delivery does not reopen that work. ^safe-vske
10. As a database caller, I want use of the originating pool inside its transaction callback reported, so that operations stay on the transaction runner. ^safe-ldtb
11. As an agent, I want aliases of that pool caught while the runner and independent pools remain legal, so that naming does not change the decision. ^safe-j6t8
12. As a maintainer, I want the safe transaction form exercised through commit and rollback, so that the rule protects database behaviour. ^safe-r1xw
13. As a Service author, I want wall-clock values used in paired subtraction/comparison or sleep/timeout arguments reported, so that clock corrections cannot distort elapsed-time decisions. ^safe-p9cw
14. As a maintainer, I want a small typed local-flow check rather than a general provenance framework, so that calendar timestamps and monotonic values remain legal. ^safe-8peq
15. As an agent, I want Mono and Mtime.span used for elapsed time, so that the replacement matches the real clock failures already repaired in Ox. ^safe-5a9k
16. As a Service author, I want known indefinite waits and no-stop servers inside cancellation protection reported, so that shutdown is not masked for the service lifetime. ^safe-ctc4
17. As a maintainer, I want bounded cleanup and effective inner deadlines accepted, so that teardown remains cancellation-safe. ^safe-vj9b
18. As a reviewer, I want this concrete catalogue distinguished from a termination or settlement proof, so that unrelated opaque work is not labelled unverified. ^safe-tcqo
19. As a database caller, I want dynamic concatenation/formatting reaching raw SQL sinks reported, so that values use parameters rather than SQL text. ^safe-8pmk
20. As a maintainer, I want static migrations, compiled query generation and parameter binding accepted, so that this rule does not impose a new SQL API design. ^safe-p1m1
21. As a reviewer, I want the finding to claim dynamic unparameterized construction rather than proven injection, so that the diagnostic is truthful. ^safe-iq5u

## Delivery

| Ticket | Slice |
| --- | --- |
| [02](<02-explicit-error-disposal.md>) | Restore legacy disposal; remove the allowance interpreter and all new attributes |
| [11](<11-worker-context.md>) | Eio calls in native workers |
| [12](<12-fiber-blocking.md>) | Known blocking calls in Eio |
| [13](<13-callback-contracts.md>) | Committed callback fixes only; no extension |
| [14](<14-transaction-runner.md>) | Originating pool used instead of transaction runner |
| [15](<15-monotonic-elapsed-time.md>) | Small wall-clock elapsed-use check |
| [16](<16-cancel-mask-scope.md>) | Protection around known long-lived work |
| [17](<17-raw-sql-construction.md>) | Dynamic text reaching raw SQL |

Identity_external may remain as the existing twelve-line check without a ticket. Partial-access ports are discarded; behaviour-preserving derive/compiler replay fixes already landed stay. Native leases, retry safety and API-bypass closure are not this delivery; they belong to their resource, once-forks, spawner and adaptive-retry specs.

## Activation and completion

For each surviving rule, refresh exact declared CMT/CMTI producers in Pie (packages), Exergy (lib bin) and Nema (lib bin), then run the current Ox engine with --root <consumer> --rules <rule> --inventory <dirs>. Discover generated-source membership only through explicitly named nonrecursive check aliases derived from selected sources’ compilation-stanza ancestors (including test/tests and includes), with Dune compiler rules proving membership, never a global recursive @check. Virtual compiler wrapper sources are not alias directories. Record decided/undecided file counts and production/test findings; inspect every production finding and classify it as defect or false positive. Ordinary consumer-file unverified evidence prevents activation. A zero-defect rule needs a concrete Eio/Ox failure scenario or is deleted. Genuine isolated compiler-rejection fixtures are identified separately, never counted as decided. Until this evidence is complete, the six detector slices are dormant in the default gate and run only through explicit --rules selection; that audit selection is not activation.

Each ticket stays one screen and cites an Ox commit or concrete failure, not another linter. Keep only necessary clean/violating consumer-style controls. Commit each deletion and surviving slice separately with these still-existing story IDs. Finish master green for install, tests, formatting and caps; remove resolved safety worktrees/branches and report the measured survivors briefly.

## Measured delivery (2026-10-06)

All15 fresh audits use SHA256 `558783c1c933c4f812ae3e7bd4f80dd76a0acbd29f703e4978e15584cd19a8a7`; all30 before/after hashes and final seals match. [Complete source-read report](</var/tmp/ox-retained-final-consumer-measurements.md>), [exact ledger](</var/tmp/ox-retained-final-counts.tsv>), [diagnostic tuples](</var/tmp/ox-retained-final-sites.tsv>) and [structured raw index](</var/tmp/ox-retained-final-data.json>) retain full messages and reasons. Selections are Pie packages, Nema lib/bin and Exergy lib/bin. Existing authenticated annotations were reused; admission exits are historical, not fresh builds. Exact compiler rules and strict source/import digests remain required. No consumer repair, global consumer gate, freshness waiver or exclusion was used.

| Consumer / tickets | Decided P/T | Undecided P/T | Excluded P/T | Findings P/T | Nonfile unknown |
| --- | --- | --- | --- | --- | --- |
| pie / 14 | 83/99 | 2/0 | 0/0 | 0/0 | 0 |
| pie / 15 | 82/99 | 3/0 | 0/0 | 3/11 | 0 |
| pie / 11+12 | 83/99 | 2/0 | 0/0 | 0/0 | 0 |
| pie / 16 | 83/99 | 2/0 | 0/0 | 0/0 | 0 |
| pie / 17 | 83/99 | 2/0 | 0/0 | 0/0 | 0 |
| nema / 14 | 135/73 | 0/3 | 0/0 | 0/0 | 0 |
| nema / 15 | 135/73 | 0/3 | 0/0 | 0/0 | 0 |
| nema / 11+12 | 135/72 | 0/4 | 0/0 | 0/1 | 0 |
| nema / 16 | 135/73 | 0/3 | 0/0 | 0/0 | 0 |
| nema / 17 | 135/73 | 0/3 | 0/0 | 0/0 | 0 |
| exergy / 14 | 189/48 | 54/7 | 0/0 | 0/0 | 1 |
| exergy / 15 | 189/48 | 54/7 | 0/0 | 0/0 | 1 |
| exergy / 11+12 | 189/48 | 54/7 | 0/0 | 0/0 | 1 |
| exergy / 16 | 189/48 | 54/7 | 0/0 | 0/0 | 1 |
| exergy / 17 | 189/48 | 54/7 | 0/0 | 0/0 | 1 |

The selected universe is693 files (463P/230T), including3 isolated compiler controls; the ordinary subset is690. All37 formerly omitted Nema tests are restored. Exact sets match the preceding complete24d8 census:0 added/omitted/excluded/disposition changes. Unique unknowns are65 ordinary (57P/8T),3 isolated controls(T) and1 nonfile inventory failure. Pie retains a stale generated source, an orphan interface and the elapsed-flow opacity; Nema retains one ordinary recursive horizon and the three isolated controls; Exergy retains54P/7T ordinary PPX/syntax/stale-or-missing annotation failures and the scoped inventory failure. Every audit exits2; none proves activation readiness.

All consumer production findings are [Pie clipboard confirmation:216](</home/ribelo/projects/ribelo/pie/packages/pie/input/text_injection.ml#L216>), [222](</home/ribelo/projects/ribelo/pie/packages/pie/input/text_injection.ml#L222>) and [227](</home/ribelo/projects/ribelo/pie/packages/pie/input/text_injection.ml#L227>):3 true occurrences of one wall-clock deadline defect,0 FP; the same file is opaque at225. Eleven elapsed test findings and one intentional Nema owner wait are test-only. The native category has0 emitted findings, not universal safety evidence.

The [Root SQL audit](</var/tmp/ox-retained-final-root-sql-inventory.tsv>) decides all20 sources and reports3 production FP at [migrate:403](<../../../lib/sql/migrate.ml#L403>), [406](<../../../lib/sql/migrate.ml#L406>) and [408](<../../../lib/sql/migrate.ml#L408>): generic raw forwarding with safely escaped [structural identifiers](<../../../lib/sql/migrate.ml#L396>) and separately supplied values. No safe migration was changed. Zero-consumer-finding slices remain because their compact corpora reproduce real failures: originating-pool reborrow timeout124; owner semaphore wait timeout124; native Eio yield Effect.Unhandled; protected indefinite wait timeout124; concatenated SQL2 rows versus bound0. Four Root gates passed with34 registered/28 active/6 dormant,0 findings/typed unknowns and0 coverage holes. This completes retained dormant delivery, not activation.

Committed slices: pruning/restoration f1c4f127; transaction8fa19d0c; elapsed845b906 (runtime repairsab84940/e55ac0e preserved); exact inventory1273687; shared owner/nativeef0efd0; cancellationa560b52; SQL1610439. Independent SPEC and Standards accepted the code delta; final ledger/gate acceptance is recorded at landing. Candidate safety branches/worktrees are removed; unrelated detached work is untouched.
