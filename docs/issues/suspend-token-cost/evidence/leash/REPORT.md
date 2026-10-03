# Leash suspension-token adoption cost

## Result

**Estimated: 329 named implementation functions/aliases need an io parameter and 887 source application nodes call io functions, across exactly 24.803 production OCaml kloc.** Densities: **13.265 named io bindings/kloc** and **35.762 io applications/kloc**. This is an untyped source-graph estimate, not a typed whole-program proof.

| Measure | Value | Evidence status |
|---|---:|---|
| Production physical lines/files | 24,803 / 83 | Exact inventory |
| Implementation lines/files | 20,573 / 43 | Exact |
| Interface lines/files | 4,230 / 40 | Exact |
| Raw named io bindings, charging deferred callbacks to factory owners | 342 (13.789/kloc) | Estimated classification |
| Adjusted named io bindings | **329 (13.265/kloc)** | Estimated classification |
| Standalone references to io functions | **99** | Estimated classification of bare function-value references |
| Adjusted io application nodes, including partial applications | **887 (35.762/kloc)** | Estimated classification of exact AST nodes |
| Raw io application nodes | 909 (36.649/kloc) | Estimated classification |
| Named locals included in adjusted set | 82 | Exact count within estimated set |
| Named identifier aliases included | 1 | Exact count within estimated set |
| Matching public interface declarations | 100 | Estimated additional edit locations, not additional functions |
| Generic callback helpers / operator aliases | 6 / 28 candidates | Not 34 proven necessary edits |
| Primitive protected callbacks plus named status functions | 34 | Exact syntactic inventory |
| Manual tab-lock callback instantiations | 8 | Exact syntactic inventory |
| Inspected regions combined, overlaps retained | 42: 16 must-not-suspend, 26 may-suspend | Inventory under stated rule |
| Direct applications conflicting with must-not-suspend | **7**, plus 3 underlying status warning sites | Manually traced |
| Prototype original size / added / deleted lines | 72 / 29 / 29 | Exact diff |
| Prototype diff-lines/original-lines | **58/72 = 80.56%** | Exact, experiment-specific |
| Positive compile / critical negative / letop negative | **exit 0 / exit 2 / exit 2** | Measured, compiler **5.4.0+ox** |

The 329 count avoids counting an implementation and its public val declaration as two functions. An edit-budget view includes approximately **329 + 100 = 429 implementation/interface declaration locations (17.296/kloc)**, before anonymous callback and record-field type edits. This is not a complete textual migration budget.

## Denominator and scope

Only production OCaml under Leash packages is included: no tests, vendor directories, or build output. Physical lines include blanks and comments. The gross inventory has 85 files and **41,391 lines**. Approved embedded-vendor exclusions are [public_suffix_data.ml:1](</tmp/suspend-token-cost/leash/source/packages/leash/public_suffix_data.ml#L1>) (16,586 lines) and [public_suffix_data.mli:1](</tmp/suspend-token-cost/leash/source/packages/leash/public_suffix_data.mli#L1>) (2), generated Mozilla Public Suffix List data. Removing them leaves **83 files, 24,803 lines = 24.803 kloc**. Keeping vendor data would dilute the adjusted densities to **7.949 bindings/kloc** and **21.430 applications/kloc**, without reducing migration work.

The census uses the observed working tree, including unrelated uncommitted work, not a clean HEAD. Concurrent source edits were detected during final validation, so all production sources were frozen in a read-only evidence copy. **Freeze interval: 2026-10-03T23:24:53.864Z to 2026-10-03T23:24:55.664Z (UTC); Leash HEAD: 33635b527d7ba30ff1ca9a6a5a4a918558309983.** It is a sequential, non-atomic working-tree read, not an assertion that the dirty tree matches HEAD. All counts use these frozen files; no later edits are chased. The file mapping is in [inventory.json](</tmp/suspend-token-cost/leash/inventory.json>) and provenance in [freeze.json](</tmp/suspend-token-cost/leash/freeze.json>). Source citations below point to the frozen copies; census rows retain original production paths.

The per-file inventory and exact line totals are in [inventory.json](</tmp/suspend-token-cost/leash/inventory.json>).

## Counting method and evidence limits

The shared parser produced **26,088 AST rows, 1,427 named function/alias candidates, and 11,126 application nodes**. Functions include named locals and identifier aliases. Calls and function references form graph edges; a fixed point propagates io from Eio suspension, io Ox wrappers, AI transport, audited operation fields, and potentially yielding logging. Bare function references propagate signatures but are not application sites. Partial applications and nested curried applications count as distinct application nodes, not as one source line. For example, [drive.ml:38](</tmp/suspend-token-cost/leash/source/packages/leash/drive.ml#L38>) has three nested applications of t.act; do not deduplicate by start offset alone.

**Fork creation suspends:** there are **10 direct registrations**, 2 Eio.Fiber.fork and 8 fork_daemon. No direct fork_promise, Scope.fork, Scope.fork_error, or Spawner.fork occurrence was found. Eager Actor/Agent/correlator/supervisor/telemetry creation is also seeded; it is not confused with deferred pure factories.

**Release registration may execute synchronously:** one Eio.Switch.on_release at [main.ml:1482](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1482>) invokes Tabs.stop if the switch is already finished. Such releases execute under Cancel.protect, which does not make them unyielding. That registration conservatively requires io. No direct Scope.on_release or Resource.use_in_scope registration occurs.

The complete adjusted named-function list is [io-signatures.tsv](</tmp/suspend-token-cost/leash/io-signatures.tsv>); the application census is [io-call-sites.tsv](</tmp/suspend-token-cost/leash/io-call-sites.tsv>). [graph.json](</tmp/suspend-token-cost/leash/graph.json>) retains raw/adjusted functions, resolved targets, factories and all AST uses. [analyze.mjs](</tmp/suspend-token-cost/leash/analyze.mjs>) reproduces the estimate from [ast.jsonl](</tmp/suspend-token-cost/leash/ast.jsonl>). [census.json](</tmp/suspend-token-cost/leash/census.json>) is an abandoned **incomplete** artifact and is not used.

**Estimated, not semantically exact:** resolution approximates lexical shadowing, module aliases and opens without compiler identities. Dynamic fields are seeded by audited spellings rather than typed dispatch. The collector recognizes named bindings with function or identifier RHSs; a named partial-application binding whose RHS is an application can be omitted as a function candidate, although its application is counted. Anonymous immediate callbacks are charged to their containing named binding; deferred callbacks are the exception below. Record-field callback signatures and added invocation adapters are work not represented by the 329 named let bindings. The 100 public-interface matches are name-based and can miss nested/field declarations; the locations are listed in [interface-edits.json](</tmp/suspend-token-cost/leash/interface-edits.json>).

The criterion is **scheduler suspension**, not synchronous domain blocking. Capability-wrapped Unix/Sys/Stdlib file operations are outside it and remain a separate blocking-risk audit. No typed whole-Leash build or production rewrite was attempted. Raw Eio calls are not intrinsically checked by the yielding mode: **the token guarantee also needs a raw-concurrency gate requiring io-taking wrappers**.

### Adjusted module totals

| Module | Named io bindings | io application nodes |
|---|---:|---:|
| Actions | 61 | 161 |
| Main | 18 | 41 |
| Cdp.Frame | 2 | 4 |
| Cdp | 5 | 5 |
| Chrome | 17 | 71 |
| Chrome.Log | 1 | 1 |
| Chrome_stderr | 2 | 3 |
| Config | 9 | 17 |
| Control | 10 | 52 |
| Desktop | 8 | 18 |
| Dialog_race | 1 | 2 |
| Dispatch | 1 | 2 |
| Download_setup | 3 | 9 |
| Drive | 10 | 31 |
| Expiry | 3 | 4 |
| Learning | 14 | 44 |
| Models | 7 | 16 |
| Planner | 3 | 5 |
| Playbook | 6 | 6 |
| Reading | 26 | 45 |
| Run | 12 | 50 |
| Tabs | 106 | 293 |
| Telemetry | 1 | 1 |
| Text_helper | 3 | 6 |

## Denominator and Logger-policy sensitivity

The **.ml-only denominator is 20.573 kloc**; adding 4.230 interface kloc gives the main **24.803 kloc** denominator. Bare standalone references are AST function-value occurrences outside callee position; they are **not applications** and must not be added to 887. They include values passed to higher-order APIs and stored callbacks, so their mode/type migration is distinct from passing ~io at a call. Current locations are in [io-references.tsv](</tmp/suspend-token-cost/leash/io-references.tsv>).

| Logger API variant | Named io bindings | io applications | Standalone io references | Bindings/apps/refs per combined kloc | Bindings/apps/refs per .ml-only kloc |
|---|---:|---:|---:|---|---|
| Current potentially yielding Logger | **329** | **887** | **99** | 13.265 / 35.762 / 3.991 | 15.992 / 43.115 / 4.812 |
| Hypothetical never-suspending Logger emit | **310** | **825** | **97** | 12.498 / 33.262 / 3.911 | 15.068 / 40.101 / 4.715 |

The second variant assumes Logger.* **never suspends**: emit try-adds a record to a bounded queue without waiting for capacity or a contended mutex; one writer fiber drains it and performs actual output. Queue-full loss/error policy must be explicit. It requires an implementation/API change, not merely observing today's reporter threshold. Writer startup, shutdown and flush still require io; these static sensitivity counts reclassify existing Logger applications and their graph propagation, **not new writer code**. Logging wrapper and t.warn callbacks become non-suspending too. The delta is **19 named bindings, 62 application nodes, 2 standalone references**. Actor's Info and Learning's warning branches cease to be Logger-related critical conflicts; status's mutex acquisition and the four declared-synchronous Actor asks remain. The alternate applications/references are listed in [nonblocking-logger-sites.tsv](</tmp/suspend-token-cost/leash/nonblocking-logger-sites.tsv>); both resolved graphs are retained in [graph.json](</tmp/suspend-token-cost/leash/graph.json>).

## Deferred factories: fresh io at invocation

The raw graph charges stored anonymous callback work to construction and propagates it to factory callers. Removing **13 factory owners** yields **342 → 329 bindings** and **909 → 887 applications**. Named local operation helpers inside factories stay counted; applications inside deferred bodies stay counted. Merely constructing the pure factory no longer requires io.

| Factory owner | Definition |
|---|---|
| Main.command | [main.ml:741](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L741>) |
| Main.playbook_command | [main.ml:772](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L772>) |
| Main.traces_command | [main.ml:944](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L944>) |
| Main.commands | [main.ml:1071](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1071>) |
| Main.skill_command | [main.ml:1629](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1629>) |
| Desktop.create | [desktop.ml:147](</tmp/suspend-token-cost/leash/source/packages/leash/desktop.ml#L147>) |
| Desktop.notifier | [desktop.ml:206](</tmp/suspend-token-cost/leash/source/packages/leash/desktop.ml#L206>) |
| Models.text_helper | [models.ml:202](</tmp/suspend-token-cost/leash/source/packages/leash/models.ml#L202>) |
| Models.levels | [models.ml:344](</tmp/suspend-token-cost/leash/source/packages/leash/models.ml#L344>) |
| Planner.create | [planner.ml:126](</tmp/suspend-token-cost/leash/source/packages/leash/planner.ml#L126>) |
| Tabs.reading_browser | [tabs.ml:1585](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1585>) |
| Tabs.action_view | [tabs.ml:1718](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1718>) |
| Text_helper.create | [text_helper.ml:197](</tmp/suspend-token-cost/leash/source/packages/leash/text_helper.ml#L197>) |

Desktop stores focus/notify operations; notifier returns a callback. Models, Text_helper and Planner build operation records. Reading/action adapters store transport and refresh callbacks. Main builds Cmdliner commands/terms whose run callbacks execute later. Each deferred field or returned closure takes a **fresh io parameter at invocation**. Never capture a construction-time token in a persistent record, and do not add io to the pure factory's callers.

```ocaml
(* Pure construction; fresh token passed at field invocation. *)
let make client =
  { complete = (fun ~io request -> complete ~io client request) }
```

Field-type/callback edits remain necessary for browser.call/sleep/probe, tab refresh/reread/operation callbacks, text completion, model levels, planner plan, and desktop operations. They are not extra named bindings in 329. Chrome.create, Cdp.create, Expiry.create, Tabs.create and Telemetry.create are **not exempt**, because they eagerly create/fork/start io resources.

## Generic helpers: yielding callback modes, not io parameters

There are **6 ordinary generic callback helpers and 28 binding-operator aliases (34 candidates)**. They do not acquire io merely because a supplied callback yields. Their callback types must permit yielding where needed. Current clearly yielding ordinary uses include **Drive.measured** and **Main.protect**. Models.with_key, Traces.protect and Learning.protect currently wrap pure/synchronous work; Model_usage.with_meter has no production registration. Therefore **34 is a candidate count, not 34 proven edits**.

Ten operator declarations are on yielding-operation paths: Download_setup.let*, Actions.let*/let+, Reading.let*, Tabs.let*, Control.let*, Learning.let*, Main.let*, Planner.let* and Run.let*. The other parser/codec aliases are not made io simply by being bind-style helpers. The compiler prototype specifically proves that ordinary letop syntax cannot capture the yielding token even with standard Result.bind.

| Declaration | Location | Kind |
|---|---|---|
| Actions.let* | [actions.ml:8](</tmp/suspend-token-cost/leash/source/packages/leash/actions.ml#L8>) | operator alias |
| Actions.let+ | [actions.ml:9](</tmp/suspend-token-cost/leash/source/packages/leash/actions.ml#L9>) | operator alias |
| Main.protect | [main.ml:33](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L33>) | generic callback helper |
| Main.let* | [main.ml:1381](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1381>) | operator alias |
| Config.let* | [config.ml:182](</tmp/suspend-token-cost/leash/source/packages/leash/config.ml#L182>) | operator alias |
| Config.let* | [config.ml:359](</tmp/suspend-token-cost/leash/source/packages/leash/config.ml#L359>) | operator alias |
| Control.let* | [control.ml:3](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L3>) | operator alias |
| Download_setup.let* | [download_setup.ml:4](</tmp/suspend-token-cost/leash/source/packages/leash/download_setup.ml#L4>) | operator alias |
| Drive.measured | [drive.ml:162](</tmp/suspend-token-cost/leash/source/packages/leash/drive.ml#L162>) | generic callback helper |
| Jev_request.let* | [jev_request.ml:632](</tmp/suspend-token-cost/leash/source/packages/leash/jev_request.ml#L632>) | operator alias |
| Learning.let* | [learning.ml:72](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L72>) | operator alias |
| Learning.protect | [learning.ml:78](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L78>) | generic callback helper |
| Model_usage.with_meter | [model_usage.ml:8](</tmp/suspend-token-cost/leash/source/packages/leash/model_usage.ml#L8>) | generic callback helper |
| Models.with_key | [models.ml:47](</tmp/suspend-token-cost/leash/source/packages/leash/models.ml#L47>) | generic callback helper |
| Planner.let* | [planner.ml:87](</tmp/suspend-token-cost/leash/source/packages/leash/planner.ml#L87>) | operator alias |
| Playbook.let* | [playbook.ml:8](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L8>) | operator alias |
| Playbook.let* | [playbook.ml:29](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L29>) | operator alias |
| Playbook.let* | [playbook.ml:74](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L74>) | operator alias |
| Playbook.let* | [playbook.ml:249](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L249>) | operator alias |
| Playbook.let* | [playbook.ml:338](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L338>) | operator alias |
| Playbook.let* | [playbook.ml:644](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L644>) | operator alias |
| Playbook.let* | [playbook.ml:797](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L797>) | operator alias |
| Playbook.let* | [playbook.ml:1082](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L1082>) | operator alias |
| Playbook.let* | [playbook.ml:1849](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L1849>) | operator alias |
| Playbook.let* | [playbook.ml:1917](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L1917>) | operator alias |
| Protocol.let* | [protocol.ml:1268](</tmp/suspend-token-cost/leash/source/packages/leash/protocol.ml#L1268>) | operator alias |
| Protocol.let* | [protocol.ml:1468](</tmp/suspend-token-cost/leash/source/packages/leash/protocol.ml#L1468>) | operator alias |
| Reading.let* | [reading.ml:20](</tmp/suspend-token-cost/leash/source/packages/leash/reading.ml#L20>) | operator alias |
| Run.let* | [run.ml:331](</tmp/suspend-token-cost/leash/source/packages/leash/run.ml#L331>) | operator alias |
| Shape.let* | [shape.ml:16](</tmp/suspend-token-cost/leash/source/packages/leash/shape.ml#L16>) | operator alias |
| Snapshot_dom.let* | [snapshot_dom.ml:11](</tmp/suspend-token-cost/leash/source/packages/leash/snapshot_dom.ml#L11>) | operator alias |
| Tabs.let* | [tabs.ml:707](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L707>) | operator alias |
| Traces.let* | [traces.ml:49](</tmp/suspend-token-cost/leash/source/packages/leash/traces.ml#L49>) | operator alias |
| Traces.protect | [traces.ml:51](</tmp/suspend-token-cost/leash/source/packages/leash/traces.ml#L51>) | generic callback helper |

Higher-order Stdlib map/iter/Option.iter/Fun.protect applications can need callback-mode adapters or explicit recursion, without those combinators becoming io functions. Cleanup Option.iter becomes an explicit match in the prototype. These changes are not predicted just by counting ~io additions.

## Critical sections and protected suspension

**Kind rule:** Actor.handle, Agent callbacks and status functions must not suspend. **Declared contract rule:** five protected tab-mutex bodies explicitly described as synchronous at [tabs.ml:720](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L720>)–[tabs.ml:724](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L724>) must not suspend. Eio.Mutex bodies otherwise may suspend; Cancel.protect masks cancellation rather than making a body unyielding. Condition waits and cancellable transport writes remain valid io.

The **42 inspected regions** comprise **1 Actor handler, 2 Agent callbacks, 8 named status functions, 5 explicitly synchronous tab-mutex callbacks, 11 Cancel.protect callbacks, 7 other Eio.Mutex callbacks, and 8 manual tab-lock callback instantiations**. Region memberships overlap. Of the eight status-named definitions, Drive.status and Run.status are pure enum decoders, not service reporters; six are actual service/CLI status readers. Two explicit Eio.Mutex.lock applications occur at [tabs.ml:726](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L726>) and [tabs.ml:2539](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2539>); the latter is a cancellation-protected reacquisition. No production Stdlib.Mutex, Ox.Mutex, or separate C-state guard was found. One Unix advisory file-lock helper at [playbook.ml:1572](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L1572>) invokes fn under a file lock; it is not a short scheduler-atomic mutex contract. Its current operations are synchronous filesystem work; its abstract callback is not proven unyielding.

The meter callback contract at [model_usage.ml:1](</tmp/suspend-token-cost/leash/source/packages/leash/model_usage.ml#L1>)–[model_usage.ml:2](</tmp/suspend-token-cost/leash/source/packages/leash/model_usage.ml#L2>) explicitly says “without yielding.” There is no production with_meter registration, so **zero instantiated meter regions**. Its computation callback fn is separate and may yield.

### Seven immediate conflicting application sites

1. **Actor kind rule:** [tabs.ml:459](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L459>) Logger.info in fold, passed as handle at [tabs.ml:3011](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L3011>). This conflicts with an **unspecialized io-taking Logger API**, but **does not suspend with Leash's current reporters**, as explained below.
2. **Status kind rule:** [learning.ml:441](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L441>) Eio.Mutex.use_ro can wait while acquiring pending_mu. The callback only reads a counter; acquisition is the suspension risk.
3. **Status kind rule:** [learning.ml:442](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L442>) proposals can warn on bad proposal files. Its underlying warning applications are [learning.ml:129](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L129>), [learning.ml:151](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L151>), and [learning.ml:164](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L164>) t.warn. The adapter at [main.ml:1479](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1479>) calls Logger.warn. These error branches can journal-suspend.

**Declared-synchronous sections that suspend:**

| Mutex registration | Conflicting application | Trace |
|---|---|---|
| [tabs.ml:1076](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1076>) | [tabs.ml:1077](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1077>) transition | transition → call → Ox.Actor.ask |
| [tabs.ml:1095](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1095>) | [tabs.ml:1097](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1097>) transition | same chain |
| [tabs.ml:1187](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1187>) | [tabs.ml:1188](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1188>) call | call → Ox.Actor.ask |
| [tabs.ml:1303](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1303>) | [tabs.ml:1305](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1305>) transition | same chain |

The call/transition implementations are at [tabs.ml:559](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L559>)–[tabs.ml:566](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L566>). These are violations despite using Eio.Mutex, because their source declares synchronous bookkeeping. The fifth callback at [tabs.ml:1088](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1088>) only assigns close_on_resume. Neither Agent callback suspends. In total: **6 direct sites can potentially runtime-suspend, and 1 filtered-logging site conflicts only at compile time under the general API**. This does not mean all six always suspend.

### Every inventoried protected body and its lexical io applications

The table includes forbidden and legitimate suspension, including io function applications that can complete immediately. [critical-reachable-sites.tsv](</tmp/suspend-token-cost/leash/critical-reachable-sites.tsv>) enumerates every classified reachable application **by region and file:line**. There are **73 distinct lexical application nodes**, or **461 distinct reachable nodes** after expanding named io callees. The expanded graph is an untyped over/under-approximation, not proof that every operation executes while the lock is held: stored/async callbacks and temporarily unlocked phases are not flow-sensitive. Full applications and transitive paths are in [critical-regions.json](</tmp/suspend-token-cost/leash/critical-regions.json>); lexical-only rows are in [critical-sites.tsv](</tmp/suspend-token-cost/leash/critical-sites.tsv>). The reproducible audit is [audit.mjs](</tmp/suspend-token-cost/leash/audit.mjs>).

| Region registration/definition | Kind | Contract | Classified lexical io applications |
|---|---|---|---|
| [chrome.ml:220](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L220>) | Agent fn | must-not-suspend | None classified; opaque callbacks discussed below. |
| [chrome.ml:409](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L409>) | Agent fn | must-not-suspend | None classified; opaque callbacks discussed below. |
| [chrome.ml:518](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L518>) | Cancel.protect | may-suspend | [chrome.ml:519](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L519>) (push) |
| [chrome.ml:544](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L544>) | Cancel.protect | may-suspend | [chrome.ml:547](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L547>) (Eio.Promise.await) |
| [control.ml:139](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L139>) | Cancel.protect | may-suspend | [control.ml:146](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L146>) (Ox_observability.Logger.warn); [control.ml:153](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L153>) (warn); [control.ml:160](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L160>) (warn) |
| [control.ml:193](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L193>) | Cancel.protect | may-suspend | [control.ml:193](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L193>) (Tabs.close) |
| [control.ml:213](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L213>) | Cancel.protect | may-suspend | [control.ml:213](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L213>) (Tabs.close) |
| [download_setup.ml:32](</tmp/suspend-token-cost/leash/source/packages/leash/download_setup.ml#L32>) | Cancel.protect | may-suspend | [download_setup.ml:34](</tmp/suspend-token-cost/leash/source/packages/leash/download_setup.ml#L34>) (call) |
| [learning.ml:36](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L36>) | Eio.Mutex.use_rw | may-suspend | None classified; opaque callbacks discussed below. |
| [learning.ml:45](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L45>) | Eio.Mutex.use_rw | may-suspend | [learning.ml:47](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L47>) (Eio.Condition.await) |
| [learning.ml:51](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L51>) | Eio.Mutex.use_rw | may-suspend | None classified; opaque callbacks discussed below. |
| [learning.ml:56](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L56>) | Eio.Mutex.use_rw | may-suspend | None classified; opaque callbacks discussed below. |
| [learning.ml:62](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L62>) | Eio.Mutex.use_rw | may-suspend | None classified; opaque callbacks discussed below. |
| [learning.ml:441](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L441>) | Eio.Mutex.use_ro | may-suspend | None classified; opaque callbacks discussed below. |
| [playbook.ml:1598](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L1598>) | Eio.Mutex.use_rw | may-suspend | None classified; opaque callbacks discussed below. |
| [tabs.ml:564](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L564>) | Cancel.protect | may-suspend | [tabs.ml:564](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L564>) (call) |
| [tabs.ml:810](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L810>) | Cancel.protect | may-suspend | [tabs.ml:810](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L810>) (focus_emulation) |
| [tabs.ml:1015](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1015>) | with_tab_lock callback | may-suspend | [tabs.ml:1016](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1016>) (locate); [tabs.ml:1017](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1017>) (navigate_locked) |
| [tabs.ml:1028](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1028>) | with_tab_lock callback | may-suspend | [tabs.ml:1029](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1029>) (locate); [tabs.ml:1031](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1031>) (page_session); [tabs.ml:1033](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1033>) (cdp_call); [tabs.ml:1037](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1037>) (Dialog_race.first); [tabs.ml:1041](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1041>) (session_call); [tabs.ml:1046](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1046>) (close_target); [tabs.ml:1050](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1050>) (disappear) |
| [tabs.ml:1076](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1076>) | Eio.Mutex.use_rw | declared-synchronous | [tabs.ml:1077](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1077>) (transition) |
| [tabs.ml:1088](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1088>) | Eio.Mutex.use_rw | declared-synchronous | None classified; opaque callbacks discussed below. |
| [tabs.ml:1095](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1095>) | Eio.Mutex.use_rw | declared-synchronous | [tabs.ml:1097](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1097>) (transition) |
| [tabs.ml:1186](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1186>) | Cancel.protect | may-suspend | [tabs.ml:1187](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1187>) (Eio.Mutex.use_rw); [tabs.ml:1188](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1188>) (call) |
| [tabs.ml:1187](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1187>) | Eio.Mutex.use_rw | declared-synchronous | [tabs.ml:1188](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1188>) (call) |
| [tabs.ml:1303](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1303>) | Eio.Mutex.use_rw | declared-synchronous | [tabs.ml:1305](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1305>) (transition) |
| [tabs.ml:1340](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1340>) | with_tab_lock callback | may-suspend | [tabs.ml:1348](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1348>) (cdp_call); [tabs.ml:1352](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1352>) (disappear) |
| [tabs.ml:1579](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1579>) | with_tab_lock callback | may-suspend | [tabs.ml:1580](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1580>) (locate); [tabs.ml:1581](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1581>) (snap_locked) |
| [tabs.ml:1631](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1631>) | with_tab_lock callback | may-suspend | [tabs.ml:1632](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1632>) (locate); [tabs.ml:1634](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1634>) (page_session); [tabs.ml:1635](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1635>) (with_focus); [tabs.ml:1643](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1643>) (browser.call) |
| [tabs.ml:1813](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1813>) | with_tab_lock callback | may-suspend | [tabs.ml:1814](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1814>) (locate); [tabs.ml:1816](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1816>) (page_session); [tabs.ml:1817](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L1817>) (with_focus) |
| [tabs.ml:2191](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2191>) | with_tab_lock callback | may-suspend | [tabs.ml:2192](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2192>) (locate); [tabs.ml:2193](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2193>) (drive_locked) |
| [tabs.ml:2235](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2235>) | with_tab_lock callback | may-suspend | [tabs.ml:2236](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2236>) (locate); [tabs.ml:2247](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2247>) (page_session); [tabs.ml:2320](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2320>) (snap_locked); [tabs.ml:2334](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2334>) (Reading.text); [tabs.ml:2362](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2362>) (Actions.click); [tabs.ml:2363](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2363>) (Actions.fill); [tabs.ml:2364](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2364>) (Actions.press); [tabs.ml:2365](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2365>) (Actions.select); [tabs.ml:2366](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2366>) (Actions.scroll); [tabs.ml:2368](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2368>) (navigate_locked); [tabs.ml:2394](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2394>) (observe); [tabs.ml:2446](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2446>) (levels.Run.score); [tabs.ml:2456](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2456>) (Dialog_race.first); [tabs.ml:2466](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2466>) (observe); [tabs.ml:2495](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2495>) (navigate_locked); [tabs.ml:2498](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2498>) (levels.Run.choose); [tabs.ml:2504](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2504>) (text_helper.Text_helper.complete); [tabs.ml:2507](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2507>) (drive_locked); [tabs.ml:2513](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2513>) ... (line truncated to 2000 chars)
| [tabs.ml:2539](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2539>) | Cancel.protect | may-suspend | [tabs.ml:2539](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2539>) (Eio.Mutex.lock) |
| [tabs.ml:2717](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2717>) | Cancel.protect | may-suspend | None classified; opaque callbacks discussed below. |
| [tabs.ml:3009](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L3009>) | Actor handle | must-not-suspend | [tabs.ml:459](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L459>) (Ox_observability.Logger.info) |
| [skill_install.ml:345](</tmp/suspend-token-cost/leash/source/packages/leash/bin/skill_install.ml#L345>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |
| [chrome.ml:527](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L527>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |
| [control.ml:405](</tmp/suspend-token-cost/leash/source/packages/leash/control.ml#L405>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |
| [drive.ml:42](</tmp/suspend-token-cost/leash/source/packages/leash/drive.ml#L42>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |
| [learning.ml:437](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L437>) | status function | must-not-suspend | [learning.ml:441](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L441>) (Eio.Mutex.use_ro); [learning.ml:442](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L442>) (proposals) |
| [models.ml:84](</tmp/suspend-token-cost/leash/source/packages/leash/models.ml#L84>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |
| [run.ml:207](</tmp/suspend-token-cost/leash/source/packages/leash/run.ml#L207>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |
| [tabs.ml:2767](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2767>) | status function | must-not-suspend | None classified; opaque callbacks discussed below. |

Opaque calls remain at Playbook locked → with_proposal → fn ([playbook.ml:1584](</tmp/suspend-token-cost/leash/source/packages/leash/playbook.ml#L1584>)), Learning.schedule work ([learning.ml:62](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L62>)), and tab-lock fn ([tabs.ml:727](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L727>)). They may yield and need appropriate callback modes; “none classified” does **not** mean pure. Tabs.run's hand_off deliberately unlocks at [tabs.ml:2536](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2536>), runs handoff/locate unlocked, then reacquires at [tabs.ml:2539](</tmp/suspend-token-cost/leash/source/packages/leash/tabs.ml#L2539>). The lexical list includes that unlocked interval. Acquisition at [learning.ml:441](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L441>) still belongs to the status region despite its callback being pure.

Legitimate protected suspension includes Condition.await at [learning.ml:47](</tmp/suspend-token-cost/leash/source/packages/leash/learning.ml#L47>), Promise.await in Chrome shutdown at [chrome.ml:547](</tmp/suspend-token-cost/leash/source/packages/leash/chrome.ml#L547>), target close in cancellation-protected download cleanup at [download_setup.ml:34](</tmp/suspend-token-cost/leash/source/packages/leash/download_setup.ml#L34>), and tab-lock browser transport. Eio.Mutex bodies are not globally mislabeled critical: only the five source-declared synchronous ones are.

## Logging

**14 direct Ox Logger applications + 8 dynamic t.warn applications = 22 logging entry applications.** Adding **5 Chrome.Log.lifecycle wrapper applications** gives **27 logging-related source applications** if wrappers are also counted. Removing all logging seeds reduces the adjusted estimate **329 → 310**: **19 named bindings** require io solely because of potential logging. These are static API counts, not a claim that every Info/Debug log emits.

Inside must-not-suspend paths: **1 lexical Logger.info site** in Actor.fold and **3 reachable t.warn sites** in status → proposals, hence **4 logical logging entry sites**. The three warning entries share one Logger.warn adapter at [main.ml:1479](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1479>); including that forwarding source location gives 5 applications but not five independent log-record events.

Leash configures **journal_level:Warn** at [main.ml:1878](</tmp/suspend-token-cost/leash/source/packages/leash/bin/main.ml#L1878>). Actor.fold's Info therefore does **not** run the journal reporter here. The optional OTLP queue performs a length guard and Stream.add with no suspension between, so the guarded add **cannot block and is not counted as a potential runtime suspension**. Its safety rests on a guard not stated by the callback type. Under an unspecialized Logger API supporting other reporters/levels, Actor Info still requires io and creates a compile-time conflict. Warn remains eligible for the journal reporter, whose mutex/flow-write path can suspend; Learning.status's warning branches are potential runtime violations.

## Real-module prototype

The actual module is [download_setup.ml:1](</tmp/suspend-token-cost/leash/source/packages/leash/download_setup.ml#L1>). The unchanged 72-line copy is [download_setup_original.ml](</tmp/suspend-token-cost/leash/download_setup_original.ml>); the adapted 72-line module is [download_setup.ml](</tmp/suspend-token-cost/leash/download_setup.ml>). The token is [io.ml](</tmp/suspend-token-cost/leash/io.ml>), with all experimental CDP/Ox/Eio-facing wrappers separately in [shim.ml](</tmp/suspend-token-cost/leash/shim.ml>). **No production repository file was edited.**

```ocaml
(* io.ml *)
type io = { suspend : unit -> unit } [@@unboxed]
type t = io

(* shim.ml *)
let critical_section (f : (unit -> _) @ local once unyielding) = f ()
let bind r (f : (_ -> _) @ local once yielding) =
  match r with Ok x -> f x | Error e -> Error e
```

The real module's call, prepare, and recursive loaded explicitly take **~(io : Io.t @ yielding)** and pass ~io onward. The bookkeeping/on_target callback is short and unyielding; cleanup and polling remain yielding. on_target is annotated unyielding (not local); the critical callback at its invocation is local. Five letop continuations become explicit local-once-yielding bind applications with [@nontail], retaining their enclosing region.

### Before

From [download_setup_original.ml:38](</tmp/suspend-token-cost/leash/download_setup_original.ml#L38>)–[download_setup_original.ml:45](</tmp/suspend-token-cost/leash/download_setup_original.ml#L45>):

```ocaml
Ox.Timeout.timeout ~clock (Ox.Duration.seconds 5) (fun () ->
    let* created =
      call cdp "Target.createTarget"
        (obj [ ("url", str "chrome://downloads/"); ("background", `Bool true) ])
    in
    let* id = field "targetId" created in
    target := Some id;
    on_target id;
```

### After

From [download_setup.ml:39](</tmp/suspend-token-cost/leash/download_setup.ml#L39>)–[download_setup.ml:45](</tmp/suspend-token-cost/leash/download_setup.ml#L45>):

```ocaml
Shim.Timeout.timeout ~io ~clock (Shim.Duration.seconds 5) (fun () ->
    (bind
      (call ~io cdp "Target.createTarget"
        (obj [ ("url", str "chrome://downloads/"); ("background", `Bool true) ])
      ) (fun created ->
    (bind (field "targetId" created) (fun id ->
    Shim.critical_section (fun () -> target := Some id; on_target id);
```

Closing bind applications carry [@nontail]. The recursive helper explicitly takes io at [download_setup.ml:51](</tmp/suspend-token-cost/leash/download_setup.ml#L51>); real Eio sleep is wrapped and invoked at [download_setup.ml:69](</tmp/suspend-token-cost/leash/download_setup.ml#L69>).

### Pinned compiler evidence

From the Ox checkout:

```sh
nix develop -c sh /tmp/suspend-token-cost/leash/compile.sh
# compiler-version.txt: 5.4.0+ox
# positive=0 negative=2 bind_negative=2
```

[compile.sh](</tmp/suspend-token-cost/leash/compile.sh>) runs ocamlfind ocamlopt -package eio,yojson. Positive compiler stdout/stderr are [positive.stdout](</tmp/suspend-token-cost/leash/positive.stdout>) and [positive.stderr](</tmp/suspend-token-cost/leash/positive.stderr>), both empty, with exit 0. The version is saved in [compiler-version.txt](</tmp/suspend-token-cost/leash/compiler-version.txt>).

The negative copy [download_setup_negative.ml:45](</tmp/suspend-token-cost/leash/download_setup_negative.ml#L45>) injects Shim.sleep ~io clock 0.01 inside the real critical bookkeeping callback. Compiler **exit 2**: “The value io is yielding but is expected to be unyielding … because it is used inside the function … which is expected to be unyielding.” Full evidence: [negative.stderr](</tmp/suspend-token-cost/leash/negative.stderr>).

The separate [bind_negative.ml](</tmp/suspend-token-cost/leash/bind_negative.ml>) captures io in an ordinary Result.bind letop continuation. Compiler **exit 2**: “The value io is yielding but is expected to be unyielding … because it is used in a letop.” Full evidence: [bind-negative.stderr](</tmp/suspend-token-cost/leash/bind-negative.stderr>).

### What the successful compile establishes

It proves that this real module body, with the explicit token path and critical callback, **type-checks under the pinned OxCaml compiler**, and the two unsafe controls fail. It is a **compile-mode experiment only**: shim CDP is unlinked; timeout does not enforce a deadline; cancel_protect does not mask cancellation; protect does not implement exceptional cleanup. Sleep calls real Eio.Time.sleep. It does **not** prove runtime lifecycle correctness, cancellation safety, production linking, or whole-Leash migration.

The final [prototype.diff](</tmp/suspend-token-cost/leash/prototype.diff>) has **29 added + 29 deleted lines**, giving the requested ratio **58/72 = 80.56%**. Counting distinct replaced original lines gives **29/72 = 40.28%**, a different metric. Both source versions are 72 lines. Support code adds **2 io lines + 36 shim lines**, excluded from the real-module denominator but disclosed. This one small module is **not a project-wide churn forecast**: much of its edit cost comes from callback-mode/letop restructuring rather than token additions alone.
