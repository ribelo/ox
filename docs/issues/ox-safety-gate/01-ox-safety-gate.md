---
status: ready-for-agent
category: enhancement
package: ox_lint, ox, ox_caps, ox_blocking, ox_sql, ox_http, ox_otel, ox_json, ox_app, ox_observability, ox_ai
consumer: Ox and consumers using its installed lint gate
blocked_by: []
---

# Make unsafe Ox code fail at the strongest available seam

## Problem Statement

The architect delegates implementation to agents and cannot depend on reading their code to catch recurring defects. A program can compile and pass stylistic checks while discarding a failure, using the wrong execution context, bypassing a transaction, or releasing a native Resource whose caller has stopped waiting but whose operation is still running. A linter that teaches elegant spelling does not by itself prevent those failures.

Elenchus contains useful implemented predicates and fixtures, but its teaching-first admission policy and broad rule catalogue solve a different problem. Importing its engine, defaults or all its rules would spend effort on preferences while leaving Ox's actual safety interfaces optional. Conversely, describing an unimplemented ownership interface or dormant rule as a guarantee creates false confidence.

## Solution

Make invalid states unrepresentable where types can express the invariant, hide dangerous protocols behind existing deep interfaces, and use ox-lint to reject supported bypasses and remaining decidable failures. Retain runtime tests for timing and failure interleavings that static evidence cannot establish. The architect approved the nineteen slices and the testing seams below on 2026-10-05.

Adapt selected Elenchus predicates and evidence into the existing Ox engine; do not introduce an Elenchus dependency. Add narrow Ox-specific rules for execution context, error disposal, callback obligations, transaction identity, elapsed time, cancellation masking and SQL construction. Deliver small lease and retry-policy slices where lint alone would be the wrong mechanism. Reuse existing ownership, lifetime and bounded-value specifications for their guarantees.

## User Stories

### Shared enforcement contract

1. As the architect, I want each admitted rule to name a concrete failure, its detectable subset, a legitimate counterexample and a usable safe replacement, so that the gate prevents defects rather than accumulating opinions. ^safe-fr73

2. As an agent, I want diagnostics to distinguish a proved defect, a policy restriction and evidence that is unverified, so that a clean scan is never presented as a proof beyond the implemented analysis. ^safe-y047

3. As a consumer maintainer, I want the installed CLI and strict repository gate to exercise each active rule over fresh compiler evidence with stable identifiers, useful locations and nonzero failure outcomes, so that enforcement works outside the Ox checkout. ^safe-czoe

4. As a kernel maintainer, I want each rule to ship positive, negative, alias/shadowing and evidence-failure cases, a documented replacement and a measured corpus review, so that activation is justified by behaviour rather than a registered name. ^safe-tlyw

5. As an agent, I want a local exception to state its exact rule and invariant or best-effort policy and to fail when malformed, unknown or stale, so that silencing a finding remains accountable. ^safe-vvf8

6. As the architect, I want compiler-owned guarantees, existing Ox enforcement and formatting to remain single-owned, so that this work neither duplicates them nor imports the Elenchus engine, style catalogue or its unbounded admission policy. ^safe-m5sp

7. As a maintainer, I want safe types and interfaces to exist before their bypasses are forbidden, with prerequisite work and dormant rules named explicitly, so that policy does not demand an unavailable replacement. ^safe-t37w

8. As a delivery owner, I want every approved slice to have a separate ticket, stable story coverage and only real blocking edges, so that agents can work the frontier without confusing specification publication with implementation. ^safe-12o2

### Make best-effort error disposal explicit

9. As a Service author, I want ignored results, wildcard bindings and unused named result bindings detected by inferred type and binding identity, so that adding an underscore does not hide a lost failure. ^safe-1bc7

10. As a reviewer, I want local error-erasing matches and standard result-to-option or result-iteration forms identified as deliberate information-loss decisions, so that merely matching Error does not count as recovery. ^safe-s6km

11. As an agent, I want propagation, meaningful recovery and a narrowly scoped best-effort exception to be distinct accepted outcomes, so that legitimate cleanup or optional work does not require invented errors or arbitrary defaults. ^safe-xls8

12. As a maintainer, I want the exception mechanism restricted to explicitly eligible policy rules, with single-rule reasons and stale-exception checks, so that it cannot suppress capability, ownership or missing-evidence enforcement. ^safe-pufa

### Replace unchecked option and list extraction

13. As an agent, I want calls to the standard partial option and list accessors identified through resolved identities, so that aliases and opens do not hide partiality and similarly named user functions are not accused. ^safe-7t06

14. As a Service author, I want affected state transitions and error decoding rewritten to return or bind the required value, so that callers do not reconstruct a mutation-dependent invariant or evaluate a decoder twice. ^safe-bguw

15. As a kernel maintainer, I want genuine joined-fiber or representation invariants to have a narrow reasoned exception, so that the rule does not replace one proof obligation with an assertion or fabricated default. ^safe-35sb

16. As a reviewer, I want migration tests to preserve empty-case and failure behaviour, so that lint cleanup does not convert a defect into apparent success. ^safe-3osb

### Close unchecked representation-cast bypasses

17. As a reviewer, I want external declarations using the identity primitive inspected in implementation and interface forms, so that a different spelling of an unchecked cast does not evade the gate. ^safe-9gfb

18. As a kernel maintainer, I want legitimate representation primitives confined to an explicit trusted implementation contract with a tested invariant, so that ordinary application code cannot acquire a cast exception by naming a module Unsafe. ^safe-4zis

19. As an agent, I want an ordinary typed identity or stronger representation offered as the replacement, so that changing the external primitive name is not mistaken for fixing the unsafe operation. ^safe-01za

### Require handling of short I/O counts

20. As a protocol author, I want discarded byte counts from supported native and capability-wrapper operations reported, so that short transfers cannot silently truncate or corrupt a message. ^safe-jwwj

21. As an agent, I want a caller to handle partial transfer, EOF and zero progress or select an existing complete-transfer interface, so that binding a count without using it is not sufficient. ^safe-qmcw

22. As a maintainer, I want stream and datagram semantics kept distinct and the operation table tested, so that the suggested repair does not split a datagram or spin forever. ^safe-t50j

### Reject structural comparison of functions

23. As an agent, I want resolved standard structural comparison operations on known function operands rejected, so that a legal type instantiation does not hide a runtime Invalid_argument. ^safe-eeso

24. As a maintainer, I want physical identity, dedicated comparators and ordinary data equality left alone, so that this check is not a blanket equality preference. ^safe-doj9

25. As a reviewer, I want containers of closures and unresolved polymorphic operands outside the first analysis horizon named explicitly, so that the rule does not claim recursive comparability proof. ^safe-2led

### Reject provably out-of-bounds constant indexing

26. As a codec author, I want constant out-of-range indexes into supported literal arrays and strings detected, so that an obvious runtime bounds failure does not survive compilation. ^safe-rxya

27. As an agent, I want decoded literal length, negative indexes and the exact upper bound handled correctly, so that escapes and byte indexing do not cause false claims. ^safe-d197

28. As a maintainer, I want dynamic lengths and user-defined indexing left outside the first rule unless resolved evidence establishes their contract, so that source spelling is never treated as semantic proof. ^safe-xd2e

### Protect compiler warning policy

29. As a maintainer, I want effective warning and fatal-warning settings compared with Ox policy, so that equivalent flag spellings and restoration are judged by meaning. ^safe-tpzm

30. As a reviewer, I want source warning attributes and supported Dune compiler flag fields checked with provenance, so that file-level and build-level opt-outs are equally visible. ^safe-zua3

31. As an agent, I want justified targeted exceptions distinguished from broad suppression and unknown flag expansion, so that existing necessary compiler exceptions remain usable without certifying unreadable configuration. ^safe-zxc1

### Keep required work outside assertions

32. As an agent, I want known mutation and required I/O inside assertion conditions detected, so that a release build does not omit work on which the program depends. ^safe-pcom

33. As a reviewer, I want effect-free sequences accepted and unresolved assertion calls named unverified within the declared rule scope, so that sequencing is not confused with proof of effects. ^safe-u7cx

34. As a maintainer, I want repaired code checked with and without assertions, so that moving required work outside the assertion preserves ordinary failure behaviour. ^safe-28t6

### Keep raw representations at explicit codec seams

35. As a Service author, I want designated domain interfaces to use abstract validated types instead of raw JSON or Obj.t, so that callers cannot bypass the domain model. ^safe-1kqm

36. As a codec maintainer, I want real codec and protocol-extension seams explicitly identified by resolved module/value ownership, so that legitimate raw payload access stays possible without a json-name exemption. ^safe-gm8y

37. As an agent, I want wrapping raw JSON in a transparent alias or renaming a function not to satisfy the policy, so that the migration earns a real representation guarantee. ^safe-l2jj

### Reject Eio operations in native worker callbacks

38. As a native adapter author, I want Eio suspension and context-dependent operations rejected inside callbacks passed to known blocking-worker interfaces, so that native threads do not accidentally rely on an Eio handler. ^safe-sr6e

39. As a maintainer, I want execution of the native job distinguished from on_cancel and on_settled callbacks, so that callbacks run in an Eio context are not misclassified as worker code. ^safe-9hbm

40. As an agent, I want local callback aliases and helper calls analysed where evidence is available and opaque delegation disclosed, so that passing a named function does not silently bypass the context check. ^safe-eftp

### Reject known blocking operations in Eio contexts

41. As a Service author, I want known synchronous waits and blocking native operations reported in established Eio contexts, so that one call cannot stall unrelated fibers. ^safe-9ved

42. As a maintainer, I want operation-specific blocking facts rather than a blanket Unix ban, so that harmless system operations and sanctioned native workers stay legal. ^safe-r5ye

43. As a reviewer, I want an unavailable safe alternative to remain a named prerequisite rather than an activated prohibition, so that the SQL native-blocking caveat is not hidden by a green policy claim. ^safe-ohen

### Enforce callback behavioural contracts

44. As a kernel maintainer, I want direct known raises in a no-raise callback and known suspension in a no-suspend callback rejected, so that a plain function type does not hide these obligations. ^safe-vske

45. As a blocking-pool user, I want shutdown of the same pool from its own running callback detected in supported local identity flows, so that a callback does not wait for its own completion. ^safe-0ozq

46. As a reviewer, I want callback contracts stated per parameter and unknown helper behaviour disclosed, so that return type or prose naming does not manufacture a behavioural guarantee. ^safe-055u

47. As an agent, I want must-not-suspend-for-long distinguished from never-suspends and expected defects preserved outside designated callback restrictions, so that lint does not outlaw normal result-function defects or invent a static latency proof. ^safe-18ht

### Detect use of the wrong transaction runner

48. As a database caller, I want operations on the originating pool inside its transaction callback reported, so that intended transactional work does not execute outside the transaction or wait for another connection. ^safe-ldtb

49. As an agent, I want local aliases of that pool detected while the transaction runner and independent pools are accepted, so that spelling changes neither evade the rule nor create false positives. ^safe-j6t8

50. As a maintainer, I want corrected code demonstrated through commit and rollback outcomes at the public SQL interface, so that the rule protects actual transaction semantics. ^safe-r1xw

### Use monotonic time for elapsed-time decisions

51. As a Service author, I want known wall-clock values reaching designated elapsed-time, local deadline or refill calculations reported, so that clock corrections do not distort these decisions. ^safe-p9cw

52. As a maintainer, I want timestamp and duration provenance distinguished through typed interfaces or supported local flow rather than variable names, so that legitimate calendar operations are not rewritten. ^safe-8peq

53. As an agent, I want the existing monotonic timeout and clock interfaces used as replacements and verified under clock jumps, so that a lint fix changes the clock semantics intentionally. ^safe-5a9k

### Restrict cancellation masking around long-lived work

54. As a Service author, I want known long-lived operations inside cancellation protection reported, so that shutdown is not disabled by an over-wide mask. ^safe-ctc4

55. As a maintainer, I want necessary protected cleanup accepted according to its actual teardown contract, so that this rule does not contradict suspending-finalizer safety. ^safe-vj9b

56. As a reviewer, I want indefinite-wait evidence distinguished from unknown duration and ordinary bounded work, so that the rule neither claims termination proof nor blanket-bans protection. ^safe-tcqo

### Check dynamic construction at raw SQL sinks

57. As a database caller, I want concatenation and supported formatting of dynamic values into SQL execution text reported, so that parameter binding is not bypassed accidentally. ^safe-8pmk

58. As a SQL maintainer, I want compiled query generation, migrations and backend-specific static SQL represented by explicit trusted contracts, so that legitimate raw SQL remains possible without module-name exemptions. ^safe-p1m1

59. As a reviewer, I want the diagnostic to claim unparameterized construction rather than proven injection, so that safety advice states exactly what the analysis established. ^safe-iq5u

### Retain native resources until physical completion

60. As a native adapter author, I want an explicit lease retaining callback resources through physical completion, so that waiter timeout or cancellation cannot release a resource still in use. ^safe-zgfv

61. As a resource owner, I want cancellation before claim, submission rejection and physical completion to release the retained ownership exactly once through the correct owner context, so that resources neither leak nor close early. ^safe-sw86

62. As a maintainer, I want Drain, detach policy and settlement failures accounted for without adding a second cancellation model, so that Eio still owns interruption and native completion remains truthful. ^safe-bt9f

63. As a reviewer, I want one demonstrated native-resource user migrated and the remaining bypass inventory explicit, so that the interface is verified by a real use rather than a hypothetical generic leasing framework. ^safe-m6vf

### Make retry-safety decisions explicit

64. As a Service author, I want the policy for an identified non-idempotent retry operation to state when repetition is safe, so that partial success cannot silently duplicate an external effect. ^safe-o2b6

65. As an agent, I want operation-specific deduplication, reconciliation or refusal of retry used where needed, so that an HTTP verb, function name or result type is not mistaken for idempotency evidence. ^safe-a5mq

66. As a maintainer, I want timeout-after-commit and partial-success retry tests at an existing operation interface, so that the policy is verified against the failure window that motivates it. ^safe-3o27

67. As a reviewer, I want retry budgets and scheduling kept separate from replay safety, so that adaptive-retry work is neither duplicated nor credited with a guarantee it does not provide. ^safe-s51t

### Close bypasses after safe interfaces exist

68. As a consumer maintainer, I want raw-concurrency enforcement activated only after once-taking forks, a Spawner and guarded access exist and applicable callers have migrated, so that the compiler guarantees cannot be bypassed but no unavailable interface is demanded. ^safe-vaz6

69. As an agent, I want ownership and validated capacity, concurrency and byte-limit guarantees inherited from their existing deliveries, so that this work closes legacy escape routes instead of duplicating their implementations. ^safe-6ukl

70. As a reviewer, I want each activation backed by a compile-fail control, a clean public-interface control and installed-gate coverage, so that dormant or unverified surfaces are never advertised as enforced. ^safe-u2na

71. As a delivery owner, I want each consumer or additional lifetime/suspension prerequisite recorded before activation and any wide migration sequenced expand, migrate, contract, so that each committed slice stays verifiable without swallowing unrelated work. ^safe-8o0p

## Implementation Decisions

### Ownership and architecture

- Ox remains direct style on Eio. Eio owns scheduling and interruption; neither leases nor retry policy introduce a second cancellation model. Expected failures remain polymorphic-variant results; defects and foreign cancellation are not blanket-converted to Error.
- The existing lint registry, typed path resolution, compiler-artifact reader, interface-behaviour evidence, CLI and repository gate remain the implementation seams. Add focused rule implementations and share helpers only when actual repeated analysis warrants them. No generic analysis platform, separate parser facade, new test framework or Elenchus runtime is introduced.
- Native lease work extends the existing blocking/Resource ownership seam. SQL checks use existing pool, transaction and raw/compiled interfaces. Time work reuses the monotonic timeout and clock interfaces. Retry safety is operation-specific and separate from adaptive retry budgets.
- An existing rule is extended rather than duplicated. Catch-all handling, Obj.magic, capability authority, public exceptions, finalizer safety, lock safety and race-versus-timeout checks retain their current owners. The new context rule does not confuse a capability to perform an operation with its safety on a scheduler domain.

### Rule admission and certainty

- Each rule names its failure, supported input forms, legitimate counterexample, safe replacement, dependencies and measurable activation evidence. Small corpus frequency alone neither proves value nor justifies prohibition; zero rule defects in the reviewed corpus and a manageable explicit-exception burden are activation criteria, not a claim of universal soundness.
- Use resolved compiler identities and inferred types for semantic claims, including opens, module aliases and supported local value aliases. Text matches, names containing json, names ending in result, and source directory guesses do not prove semantics.
- The primary outcomes are decided-clean within the declared horizon, violation, unverified evidence for a relevant obligation, and named out-of-scope/dormant applicability. A violation additionally identifies whether it is a demonstrated defect or a policy restriction.
- Preserve existing CLI failure behaviour: findings are nonzero; missing, stale or invalid required evidence is an evidence failure, not a clean run. For relevant in-scope obligations, unresolved helper effects, receiver identity or configuration produce a located unverified decision that prevents strict-gate certification. Do not classify every unrelated opaque function as a violation or turn a declared out-of-scope case into a false safety guarantee.
- Unknown evidence cannot be suppressed. A rule must disclose a finite local analysis horizon; no whole-program effect, taint, termination, idempotency or resource-lifetime proof is claimed. Evidence tables must state what remains outside that horizon.

### Policy exceptions

- Error disposal and partial access may use one narrow expression/binding-scoped policy exception with one exact rule ID and a nonempty reason. The supported metadata spelling is selected with the first implementation and then stays stable; the observable contract is its scope and validation, not a comment heuristic.
- Eligible rules are explicitly enumerated. Unknown IDs, malformed payloads, wildcard lists and exceptions matching no finding under an enabled rule fail. Disabled rules do not cause false stale-exception findings. A reason documents an invariant; it does not prove it.
- There is no universal waiver for capability authority, ownership, type-safety casts, evidence freshness or source coverage. Legitimate casts, raw codecs, SQL generation and targeted warning exemptions use explicit structural contracts, not arbitrary path or naming exemptions.

### Migration and activation

- Every rule slice is vertical: predicate, installed diagnostic, evidence cases, documentation, reviewed Ox findings and safe remediation ship together. Detection is not remediation: binding a count, matching Error, renaming a cast or adding an assertion cannot by itself satisfy the intended guarantee.
- Preserve observable behaviour during safety rewrites. Option/list migrations may change state transitions to return required evidence or bind one decoded value; do not invent fallback success. Stream short-transfer repairs do not apply blindly to datagrams. Function comparison checks do not promise arbitrary function equality. SQL parameters do not substitute for identifiers.
- Before an activation, verify that each supported operation has a usable replacement and that its actual callers are migrated. The documented SQLite domain-blocking caveat is an explicit prerequisite for the affected scope, not permission to claim all blocking has been eliminated.
- Existing ownership and bounded-value deliveries are not recreated here. Raw concurrency remains deliberately dormant until once-taking forks, Spawner and guarded access are public and verified, and applicable callers have migrated. Lifetime/suspension and duplex prerequisites are added only for the guarantees actually claimed.
- Large changes use expand, migrate in bounded consumer/package batches, then contract. Each batch keeps the gate green. The approved tickets are bounded slices, not a license to execute a repository-wide signature migration in one context. Discovering wider work requires explicit child tickets and real dependency edges before expansion.
- Consumer enforcement is verified through compiled miniature consumer workspaces and the installed binary. Actual consumer-wide migrations remain owned by their existing consumer specs; no claim of adoption is made from Ox fixtures alone.

## Testing Decisions

### Approved seams

The highest seam is the installed ox-lint CLI plus strict repository gate operating on compiled consumer projects. Existing engine/concurrency fixtures and deployment tests provide the pattern for asserting exact rule IDs, relevant source locations, clean controls, evidence failure and source coverage. Rule-local tests support diagnosis but do not replace installed behaviour.

For interface changes, the seam is the public Ox interface: compile-fail cases establish expressible ownership and type refusals, and deterministic runtime tests establish transaction, cancellation, callback completion, time and error semantics. Follow the existing blocking settlement, SQL transaction, virtual-clock and concurrency suites. Do not assert internal tables, helper function structure or chosen traversal algorithms.

### Story-to-test obligations

- Every rule ticket tests safe-fr73, safe-y047, safe-czoe, safe-tlyw through a violating case, a legitimate counterexample, the advertised replacement, supported alias/shadowing controls and missing/stale/opaque evidence where applicable. Strict scope and installed execution must agree.
- Policy-exception tests cover safe-vvf8 and the error-disposal/partial-access story sets: valid narrow exception, malformed reason, unknown ID, stale exception, disabled-rule control and an attempted forbidden safety/evidence waiver.
- Shared ownership and activation checks cover safe-m5sp, safe-t37w; avoid duplicate diagnostics and distinguish an implemented decider from active enforcement.
- Ticket/story and dependency validation covers safe-12o2; all story IDs are unique and every story has at least one implementing ticket. A cited test is evidence to inspect, not proof that a story is delivered.

- **Make best-effort error disposal explicit** (safe-1bc7, safe-s6km, safe-xls8, safe-pufa): Compile representative local failure-disposal forms; exercise explicit best-effort acceptance, real recovery and stale/forbidden exceptions through the installed CLI.

- **Replace unchecked option and list extraction** (safe-7t06, safe-bguw, safe-35sb, safe-3osb): Compile partial and total forms and run affected transition/error-decoding/concurrency tests, preserving legitimate invariants and failures.

- **Close unchecked representation-cast bypasses** (safe-9gfb, safe-4zis, safe-01za): Compile ordinary typed identity and primitive declaration controls; test trusted versus untrusted structural ownership and absence of duplicate cast diagnostics.

- **Require handling of short I/O counts** (safe-jwwj, safe-qmcw, safe-t50j): Use controlled short-transfer, EOF and zero-progress streams plus datagram controls; exercise the recognised native and capability calls through lint.

- **Reject structural comparison of functions** (safe-eeso, safe-doj9, safe-2led): Compile direct arrow comparisons and ordinary/physical/dedicated comparison controls, including shadowed names and stated container limits.

- **Reject provably out-of-bounds constant indexing** (safe-rxya, safe-d197, safe-xd2e): Compile literal-bound cases with escaped string bytes, empty collections, negative and upper-bound indexes and unknown lengths.

- **Protect compiler warning policy** (safe-tpzm, safe-zua3, safe-zxc1): Build miniature configurations with equivalent/restored flags, targeted exceptions, source attributes, broad suppression and unsupported expansions.

- **Keep required work outside assertions** (safe-pcom, safe-u7cx, safe-28t6): Run normal and noassert builds with observable required work; pair a pure sequence, a known effectful predicate and an unresolved helper.

- **Keep raw representations at explicit codec seams** (safe-1kqm, safe-gm8y, safe-l2jj): Compile designated domain and codec interfaces, transparent aliases and name-impostor controls; run public codec roundtrips and invalid-input cases.

- **Reject Eio operations in native worker callbacks** (safe-sr6e, safe-9hbm, safe-eftp): Compile known native callback invocations, local helpers, pure worker work and Eio-context completion hooks; respect actual callback roles.

- **Reject known blocking operations in Eio contexts** (safe-9ved, safe-r5ye, safe-ohen): Compile Eio roots with recognised blocking calls and sanctioned workers; exercise the replacement and explicitly test inactive unsupported scope.

- **Enforce callback behavioural contracts** (safe-vske, safe-0ozq, safe-055u, safe-18ht): Compile direct known contract violations and independent-pool/handled-defect controls; exercise runtime hook behaviour without static latency claims.

- **Detect use of the wrong transaction runner** (safe-ldtb, safe-j6t8, safe-r1xw): Use a bounded SQL fixture to demonstrate transactional rollback with the transaction runner; lint captured original-pool aliases and accept independent pools.

- **Use monotonic time for elapsed-time decisions** (safe-p9cw, safe-8peq, safe-5a9k): Use virtual wall-clock jumps and a monotonic control; preserve calendar semantics and existing timeout/cancellation behaviour.

- **Restrict cancellation masking around long-lived work** (safe-ctc4, safe-vj9b, safe-tcqo): Use a controlled cancellation/release fixture to distinguish long-lived masking from necessary protected cleanup without leaving a hung test.

- **Check dynamic construction at raw SQL sinks** (safe-8pmk, safe-p1m1, safe-iq5u): Exercise quoted/delimiter-like data through parameter binding, static raw migrations and typed builders; lint supported dynamic text flows.

- **Retain native resources until physical completion** (safe-zgfv, safe-sw86, safe-bt9f, safe-m6vf): Control worker claim and settlement to test cancellation before/after claim, timeout, rejection, native failure and exact-once retained ownership release.

- **Make retry-safety decisions explicit** (safe-o2b6, safe-a5mq, safe-3o27, safe-s51t): Use an actual operation seam with deterministic failure-before-commit, commit-then-response-loss and duplicate attempt cases; assert visible effects and errors.

- **Close bypasses after safe interfaces exist** (safe-vaz6, safe-6ukl, safe-u2na, safe-8o0p): Pair compile-fail and clean public-interface consumer cases with installed gate activation and complete applicable-call-site migration evidence.

All implementation commits run the repository install build, tests, formatting check and capability/lint gate. New obligations cite the relevant bare story IDs in their tests. Publication of this specification and tickets does not require or imply implementing their future test suites.

## Out of Scope

- Importing Elenchus's engine, shell, dependency graph, stable AST facade or full rule catalogue. Its source and fixtures are reference evidence to adapt and revalidate.
- Teaching-only naming, punctuation, blanket no-open and general prefer-idiom rules in the mandatory safety gate.
- A blanket ban on raises in result-returning functions, all polymorphic comparison, all raw JSON, all raw SQL, every Unix operation, every retry or all cancellation protection.
- A universal waiver mechanism, automatic source fixes, a new cancellation runtime, a generic leasing framework or inferred proof of idempotency.
- General whole-program effect/taint analysis, arbitrary bounds/termination proof, static latency claims, or proving mandatory close/await using affine modes.
- Reimplementing the existing ownership, local scope, suspend-token, typestate, bounded-value or simulation programmes. They remain separately justified deliveries; this spec only uses and closes supported bypasses.
- Enabling unavailable replacements, mechanically rewriting partial access into assertions/defaults, or claiming that a clean finite lint pass proves absence of all bad code.

## Further Notes

### Delivery and approved ticket map

Nineteen slices were approved. The specification is file 01; ticket files are 02 through 20, so approved slice 1 is ticket 02 and approved slice 19 is ticket 20. Only slice 2 depends on slice 1. Slice 19 has existing external prerequisites. The other slices may start independently; sharing an implementation helper does not itself create a blocking edge. All tickets are ready-for-agent; blocked_by determines the runnable frontier.

| Approved slice | Ticket | Blocked by | Specific stories |
| --- | --- | --- | --- |
| 1 | [Make best-effort error disposal explicit](<02-explicit-error-disposal.md>) | None | safe-1bc7, safe-s6km, safe-xls8, safe-pufa |
| 2 | [Replace unchecked option and list extraction](<03-partial-access.md>) | Slice 1 | safe-7t06, safe-bguw, safe-35sb, safe-3osb |
| 3 | [Close unchecked representation-cast bypasses](<04-representation-casts.md>) | None | safe-9gfb, safe-4zis, safe-01za |
| 4 | [Require handling of short I/O counts](<05-short-io-counts.md>) | None | safe-jwwj, safe-qmcw, safe-t50j |
| 5 | [Reject structural comparison of functions](<06-function-comparison.md>) | None | safe-eeso, safe-doj9, safe-2led |
| 6 | [Reject provably out-of-bounds constant indexing](<07-constant-indexing.md>) | None | safe-rxya, safe-d197, safe-xd2e |
| 7 | [Protect compiler warning policy](<08-warning-policy.md>) | None | safe-tpzm, safe-zua3, safe-zxc1 |
| 8 | [Keep required work outside assertions](<09-assertion-effects.md>) | None | safe-pcom, safe-u7cx, safe-28t6 |
| 9 | [Keep raw representations at explicit codec seams](<10-codec-seams.md>) | None | safe-1kqm, safe-gm8y, safe-l2jj |
| 10 | [Reject Eio operations in native worker callbacks](<11-worker-context.md>) | None | safe-sr6e, safe-9hbm, safe-eftp |
| 11 | [Reject known blocking operations in Eio contexts](<12-fiber-blocking.md>) | None | safe-9ved, safe-r5ye, safe-ohen |
| 12 | [Enforce callback behavioural contracts](<13-callback-contracts.md>) | None | safe-vske, safe-0ozq, safe-055u, safe-18ht |
| 13 | [Detect use of the wrong transaction runner](<14-transaction-runner.md>) | None | safe-ldtb, safe-j6t8, safe-r1xw |
| 14 | [Use monotonic time for elapsed-time decisions](<15-monotonic-elapsed-time.md>) | None | safe-p9cw, safe-8peq, safe-5a9k |
| 15 | [Restrict cancellation masking around long-lived work](<16-cancel-mask-scope.md>) | None | safe-ctc4, safe-vj9b, safe-tcqo |
| 16 | [Check dynamic construction at raw SQL sinks](<17-raw-sql-construction.md>) | None | safe-8pmk, safe-p1m1, safe-iq5u |
| 17 | [Retain native resources until physical completion](<18-native-resource-leases.md>) | None | safe-zgfv, safe-sw86, safe-bt9f, safe-m6vf |
| 18 | [Make retry-safety decisions explicit](<19-retry-safety.md>) | None | safe-o2b6, safe-a5mq, safe-3o27, safe-s51t |
| 19 | [Close bypasses after safe interfaces exist](<20-close-safe-api-bypasses.md>) | Existing once-forks, owned-handles, spawner, ox-mutex and parse-dont-validate deliveries | safe-vaz6, safe-6ukl, safe-u2na, safe-8o0p |

Shared stories are cited by each applicable ticket; no story is considered implemented merely because this map exists.

### Existing authority and prerequisites

- [Direct style](<../../adr/0001-direct-style-on-eio.md>), [typed failures](<../../adr/0002-result-is-the-error-channel.md>), [types as schema](<../../adr/0008-types-are-the-schema.md>), [ownership and its limits](<../../adr/0010-modes-type-ownership-and-lifetime.md>) and [Eio-owned cancellation](<../../adr/0011-cancellation-as-a-value.md>) constrain implementation. No ADR is amended by this publication.
- Existing lint deliveries: [engine](<../ox-lint/01-ox-lint.md>), [concurrency rules](<../ox-lint-rules/01-ox-lint-rules.md>), [interface truth](<../ox-lint-docs/01-ox-lint-docs.md>), [capability enforcement](<../caps-on-ox-lint/01-caps-on-ox-lint.md>) and [coverage/dormancy](<../ox-lint-coverage/01-ox-lint-coverage.md>). Current implementation and verified behaviour take precedence over obsolete Semgrep-era design descriptions.
- Activation prerequisites: [once-forks](<../once-forks/01-once-forks.md>), [owned-handles](<../owned-handles/01-owned-handles.md>), [spawner](<../spawner/01-spawner.md>), [ox-mutex](<../ox-mutex/01-ox-mutex.md>) and [validated values](<../parse-dont-validate/01-parse-dont-validate.md>). Additional [local-scope](<../local-scope/01-local-scope.md>), [suspend-token](<../suspend-token/01-suspend-token.md>) and [duplex-halves](<../duplex-halves/01-duplex-halves.md>) prerequisites are conditional on the claimed surface, not blanket blockers for all rule work.
- [Monotonic timeout](<../monotonic-timeout/01-monotonic-timeout.md>) is reused; [adaptive retry](<../adaptive-retry/01-adaptive-retry.md>) owns budgets, not replay safety. [Usage rules](<../usage-rules/01-usage-rules.md>) and [simulation](<../simulation/01-simulation.md>) keep their existing ownership.

### Integration decisions

2026-10-05: implementation uses the user-requested integrate/ox-safety-gate branch with isolated per-ticket worktrees. Workers own disjoint logical files, even across worktrees; the lead owns commits, merges, shared contracts, ticket closure and final acceptance. Shared registry/CLI edits are serialized. Independent new lint modules compile through the existing lint_engine; this adds no analysis framework. Evidence-aware rules will use per-finding message and undecided callbacks so uncertainty cannot be represented as an ordinary waivable finding.

The AI JSON POST operation is the concrete retry-safety slice: safe default refuses ambiguous replay, explicit duplicate-effect consent is separate from attempt limits. Native-resource lease selection remains open until a real owner/use pair is established; tests alone are not treated as a production migration. Existing ownership, Spawner, guarded-access and validated-value specifications remain external prerequisites to ticket 20; their undelivered guarantees must not be advertised as active enforcement.

### Source review findings retained as hypotheses to verify

The conversation inspected Elenchus's actual rule registration and selected implementations, not just its stale catalogue totals. Partial access, identity externals, discarded I/O counts, function comparison, constant indexing and warning-policy checks supply useful ideas. Broad JSON-contract name exemptions, result-function substring detection and sequence-only assertion-effect detection must not be copied as guarantees. Ox's named-discard escape and dormant raw-concurrency rule were observed in source. Re-read implementation state before coding; these observations justify this work but do not freeze the repository at review time.
