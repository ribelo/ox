---
status: implementing
category: enhancement
package: ox_lint
consumer: Ox, Pie, Exergy, Nema
blocked_by: []
---

# Catch concrete Eio and Ox defects

## Problem statement

Agents produce transaction escapes, fiber-blocking calls, Eio calls on native workers, wall-clock elapsed arithmetic and dynamic SQL text. The gate must catch those failures, not import a catalogue of language style rules. The architect reduced this delivery on 2026-10-06 after the real consumer audit found no defects in the rejected ports.

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
16. As a database caller, I want dynamic concatenation/formatting reaching raw SQL sinks reported, so that values use parameters rather than SQL text. ^safe-8pmk
17. As a maintainer, I want static migrations, compiled query generation and parameter binding accepted, so that this rule does not impose a new SQL API design. ^safe-p1m1
18. As a reviewer, I want the finding to claim dynamic unparameterized construction rather than proven injection, so that the diagnostic is truthful. ^safe-iq5u

## Delivery

| Ticket | Slice |
| --- | --- |
| [02](<02-explicit-error-disposal.md>) | Restore legacy disposal; remove the allowance interpreter and all new attributes |
| [11](<11-worker-context.md>) | Eio calls in native workers |
| [12](<12-fiber-blocking.md>) | Known blocking calls in Eio |
| [13](<13-callback-contracts.md>) | Committed callback fixes only; no extension |
| [14](<14-transaction-runner.md>) | Originating pool used instead of transaction runner |
| [15](<15-monotonic-elapsed-time.md>) | Small wall-clock elapsed-use check |
| [17](<17-raw-sql-construction.md>) | Dynamic text reaching raw SQL |
| [19](<19-no-duplicate-external-effect-on-retry.md>) | No duplicate external effect on retry: type spec only |
| [20](<20-unbounded-read.md>) | Whole-stream reads require finite budgets |
| [21](<21-resource-release.md>) | Raw acquisitions need handle-specific local release evidence |
| [22](<22-adjacent-endpoints.md>) | Label only observed ordered same-type endpoints |

Identity_external may remain as the existing twelve-line check without a ticket. Partial-access ports are discarded; behaviour-preserving derive/compiler replay fixes already landed stay. Native leases and API-bypass closure are not this delivery; they belong to their resource, once-forks and spawner specs. Retry-effect safety is the one new type spec in ticket19, with no implementation. ^safe-z76e

## Activation and completion

Prevention decision (2026-10-06): weigh failure cost, silent propagation and what types already prevent. Activate elapsed time and transaction runners. Execution context activates only with zero ordinary production unknowns across Pie/Exergy/Nema; otherwise name blockers and keep it dormant. Activate raw SQL only after the migration/DSL seam’s compiler-resolved trusted contract removes its three false positives. Remove cancellation masks: lower severity, rare exposure and zero consumer production findings do not justify their maintenance cost. Probe adjacent same-base-type positional parameters, unbounded reads, missing release paths and wire float conversion before further construction; classify counts in one-screen tickets. Open retry-effect safety as a separate type spec, without implementing it. No file-length/style rules. Exact scoped compiler admission, strict digests and separate isolated controls remain mandatory evidence requirements, not a universal activation veto.

Each ticket stays one screen and cites an Ox commit or concrete failure, not another linter. Keep only necessary clean/violating consumer-style controls. Commit each deletion and surviving slice separately with these still-existing story IDs. Finish master green for install, tests, formatting and caps; remove resolved safety worktrees/branches and report the measured survivors briefly.

## Current measured admission (2026-10-06)

Elapsed time, transaction runners and raw SQL are active. Cancellation-mask code, fixtures and ticket are deleted. Shared execution context (native Eio and owner blocking) remains dormant. Root's earlier four serial gates passed with 33 registered rules, 31 active, 2 dormant, zero findings/typed unknowns and zero coverage holes. Follow-up activates unbounded-read, resource-without-release-path and restricted adjacent-same-type (36 registered, 34 active, 2 dormant). Commits: elapsed 468a6fe2, transactions 6bcfa142, cancellation retirement 7ad691a5, SQL 8a8a9a96. The SQL trust contract uses the genuine private producer's compiler UID; private migration helpers retain nominal table names until assembly. Three former migration false positives are gone without changing generated SQL or exempting any path/module name.

### Execution-context admission

Fresh authenticated scan: 693 selected sources (463 production, 230 tests), no exclusions. Retained numbers supersede the historical 5587-engine dispositions, not its failure witnesses. The [manual positional sample](<../../../test/lint/prevention-probes/adjacent-sample.tsv>) and [deterministic replay](<../../../test/lint/prevention-probes/sample.mjs>) are committed evidence. Every API count below is a resolved value-UID reference, including aliases, rather than a spelling match.

| Consumer | Decided P/T | File unknown P/T | Execution findings P/T | Visitor unknown P/T |
| --- | --- | --- | --- | --- |
| Pie | 83/99 | 2/0 | 0/0 | 0/0 |
| Nema | 135/73 | 0/3 | 0/1 | 0/1 |
| Exergy | 242/48 | 1/7 | 0/0 | 0/0 |

Production blockers: [Pie generated build identity](</home/ribelo/projects/ribelo/pie/_build/default/packages/pie/build_identity.ml>) has a stale source digest; [Pie skill_cli interface](</home/ribelo/projects/ribelo/pie/packages/pie/bin/skill_cli.mli>) has no typed annotation; [Exergy executable](</home/ribelo/projects/exergy/bin/exergy/main.ml>) has no typed annotation. Exergy's generated-source ownership inventory is also unavailable (targeted nonrecursive check aliases), so its unverified generated production surface is not zero. Nema has zero production unknowns. There are no production findings, but these three ordinary unknown files and the Exergy inventory failure prohibit activation.

Nema's three file unknowns are isolated Ladybug identity controls. Its ordinary [audit lifecycle:22](</home/ribelo/projects/ribelo/nema/lib/nema/test/test_audit_lifecycle.ml#L22>) is an unresolved recursive execution-context horizon; the adjacent owner wait is intentional test evidence. Exergy's seven test unknowns comprise six missing annotations and a test-support CMT reported as not a compiled interface; complete names/reasons remain in the linked rows. None is reclassified as production or silently excluded.

### Four requested probes (production / test counts)

| Consumer | Adjacent same-base positional pairs | Read API references | Acquisition API references | Float conversion references |
| --- | --- | --- | --- | --- |
| Pie | 41/142 | 4/19 | 7/13 | 0/0 |
| Nema | 92/143 | 0/2 | 8/4 | 2/1 |
| Exergy | 146/64 | 0/1 | 0/0 | 10/1 |
| Total | 279/349 | 4/22 | 15/17 | 12/2 |

- **Positional pairs:** 628 candidates (279 production), not proven defects. Manual seeded sample: 11/40 swap-prone (27.5%); threshold 25% met. Activate only [ordered endpoint declarations](<22-adjacent-endpoints.md>), not all homogeneous parameters, money pairs or Stdlib offset/length conventions.
- **Reads:** [Active UID rule and counts](<20-unbounded-read.md>); all three Pie production risks are grouped in [one docs-only issue](</home/ribelo/projects/ribelo/pie/docs/issues/unbounded-process-output/01-unbounded-process-output.md>). Finite reader budgets and validated Byte_limit boundaries remain legal; missing of_flow max_size is already untypeable.
- **Acquisition:** [Active handle-specific local policy and counts](<21-resource-release.md>). The concrete [history exceptional-close gap](</home/ribelo/projects/ribelo/pie/docs/issues/history-release-path/01-history-release-path.md>) stays docs-only. Other findings may be intentional transferred/manual lifetimes, not established runtime leaks.
- **Floats:** Drop: 14 resolved references, zero demonstrated money/quantity wire defects; no checker or Decimal/Money issue justified.

Pie clipboard confirmation remains an issue-only consumer change. Retry-effect safety is a separate type spec, not an implemented retry API or checker. The retained witnesses still distinguish real failures: pool reborrow timeout 124, owner semaphore timeout 124, native yield Effect.Unhandled, and injected SQL two rows versus bound zero.
