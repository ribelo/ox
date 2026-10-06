---
status: implementing
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
7. As a maintainer, I want operation-specific sleep, blocking-fd I/O and joins checked rather than a blanket Unix ban, so that harmless system calls and native jobs remain legal. Stdlib locks stay with the existing lock rule. ^safe-r5ye
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

For each surviving rule, build fresh Pie (packages), Exergy (lib bin) and Nema (lib bin) annotations with nix develop -c dune build @check, then run the current Ox engine with --root <ox> --rules <rule> --inventory <dirs>. Record decided/undecided file counts and production/test findings; inspect every production finding and classify it as defect or false positive. Ordinary consumer-file unverified evidence prevents activation. A zero-defect rule needs a concrete Eio/Ox failure scenario or is deleted. Genuine isolated compiler-rejection fixtures are identified separately, never counted as decided. Until this evidence is complete, the six detector slices are dormant in the default gate and run only through explicit --rules selection; that audit selection is not activation.

Each ticket stays one screen and cites an Ox commit or concrete failure, not another linter. Keep only necessary clean/violating consumer-style controls. Commit each deletion and surviving slice separately with these still-existing story IDs. Finish master green for install, tests, formatting and caps; remove resolved safety worktrees/branches and report the measured survivors briefly.
