# Nema suspension-token migration cost

## Result

Production OCaml size is **27.798 kloc**. The best untyped-source estimate is **318 affected named signatures (11.44/kloc)** and **622 distinct io application sites (22.38/kloc)**. The raw closure is **323 signatures (11.62/kloc)** and **627 applications**; excluding five deferred factories removes five signature/application edges. These are migration estimates, not a whole-program typed proof.

There is **one verified must-not-suspend violation**: the publication-wait callback calls a logging observer. There are **33 distinct legitimate io applications** in may-suspend synchronization/protection regions. The real Gate copy compiles with the pinned compiler; a positive Eio smoke test passes, and a negative critical-callback test fails for the intended yielding-mode reason.

| Measure | Count | Status |
|---|---:|---|
| Production files | 131 | Exact inventory |
| Physical lines, .ml + .mli | 27,798 | Exact inventory, comments/blanks included |
| Raw named-signature closure | 323 | Estimated, including 3 named partial bindings |
| Deferred factory owners removed | 5 | Manually classified |
| Adjusted named-signature closure | 318 | Estimated |
| Raw / adjusted io applications | 627 / 622 | Exact syntax-site counts within estimated closure |
| Direct external suspension-root applications | 65 | Validated root set; syntax count |
| Logging applications | 8 | Exact direct source applications |
| Logging directly lexically inside must-not-suspend | 0 | Exact for inventoried regions |
| Logging-observer calls inside must-not-suspend | 1 | Verified production wiring |
| Distinct log calls reachable through that observer | 2 | Logger.span and Logger.info |
| Conservative release-registration applications | 2 direct + 5 calls through local wrapper | Exact syntax; conservative effect classification |
| Audited synchronization/guard/status-query sites | 54 | Exact classified source-site inventory |
| Must-not-suspend / may-suspend audited sites | 25 / 29 | Policy split, including acquisitions and wrapper definitions |
| Must-not-suspend io application / violation sites | 1 / 1 | Observer dispatch, not a legitimate wait |
| Legitimate io applications in may-suspend regions | 33 | Distinct source positions; nested regions deduplicated |
| Generic Result-bind helpers | 70 | Definitions and aliases; not io signatures |
| Additional generic/guard callback helpers | 15 | Listed below; guard callbacks require unyielding instead |

## Scope and method

Only production sources under lib/nema, lib/ladybug, and bin/nema were inventoried. The Ladybug connector is Nema-owned production OCaml, not a vendored dependency. Tests, vendored trees, _build, C stubs, generated build output, and the build-only [gen_skill_data.ml](</home/ribelo/projects/ribelo/nema/bin/nema/gen_skill_data.ml>) are excluded. [Dune configuration](</home/ribelo/projects/ribelo/nema/bin/nema/dune#L22-L34>) gives the generator a separate executable stanza and uses it in the skill-data build rule; it is not a runtime module.

- lib/nema/: 121 files, 23,845 physical lines.
- lib/ladybug/: 3 files, 2,026 physical lines.
- bin/nema/: 7 files, 1,927 physical lines.

The .ml-only denominator is **24,509 physical lines = 24.509 kloc** (implementation source); interfaces contribute **3,289 lines = 3.289 kloc**. The combined denominator is **27,798 lines = 27.798 kloc**, used for the headline densities. The denominator counts each production .ml and .mli once, using the read-tool physical-line total. The numerator counts a named function implementation once; its matching .mli declaration does not add another signature. Locals and real aliases are eligible; anonymous immediate callbacks are charged to the containing named function. Three real partial bindings at [main.ml:745](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L745>), [main.ml:746](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L746>), and [main.ml:1057](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1057>) are added explicitly to the AST function inventory. No additional direct aliases to io functions were found.

The parsed corpus has 1,980 direct function declarations, 91 identifier-RHS alias candidates, and 14,473 application AST nodes. Alias candidates include ordinary values and pure Result.bind aliases, so these raw values are not the migration count. The fixed point follows resolved local/module applications and function references passed to immediate callbacks. Partial applications count as applications even when they only build a closure. Distinct application positions, rather than textual lines, are the counting unit.

The root set includes Eio waits, forks, mutex acquisition, condition/semaphore waits, switch completion, network/HTTP/body operations, time sleeps, blocking-worker admission/drain, Ox scoped forks/timeouts, application runtime wrappers, embedding requests, and the configured log reporters. Eio.Cancel.protect is not intrinsically a wait: its immediate body is followed, and the region is may-suspend unless separately documented critical. Stdlib Mutex blocks the domain but is not an Eio fiber suspension; its guarded callbacks must not consume io.

Release registration is conservatively effectful because Eio.Switch.on_release can run a release immediately when the switch has already finished. The two direct registrations are [main.ml:909](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L909>) and [nema_ladybug.ml:1068](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1068>). The local on_release wrapper has five application sites at main lines 980, 991, 996, 1004, and 1047; these are already in the application closure, not five extra direct registrations. No Ox.Scope.on_release or Ox.Resource.use_in_scope registrations occur in this corpus.

### Deferred factories

A stored field or command callback receives fresh io when invoked; its factory need not capture io. These five named owners are excluded from propagation, while their later-invoked named callbacks remain affected:

- Main.client_commands — [main.ml:742](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L742>); command/functor construction, not execution.
- Main.daemon_cmd — [main.ml:754](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L754>); command/functor construction, not execution.
- Main.status_cmd — [main.ml:778](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L778>); command/functor construction, not execution.
- Main.stop_cmd — [main.ml:807](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L807>); command/functor construction, not execution.
- Main.restart_cmd — [main.ml:839](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L839>); command/functor construction, not execution.

The observer record constructed at [main.ml:1019](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1019>) also receives io at field invocation in the migration design. Its enclosing Main.body is still affected because it independently performs logging, forks, networking, database admission and cleanup. Ox reporter constructors are pure factories: Ox_otel.reporter is not a root. Ox_otel.create is a root because it forks the exporter. Embeddings.create is not a misleading pure constructor here: [embeddings.ml:60](</home/ribelo/projects/ribelo/ocaml/ox/lib/ai_openrouter/embeddings.ml#L60>) takes the request and invokes HTTP Common.post.

### Limits of the estimate

The collector parses but does not typecheck Nema. Lexical resolution is approximate for shadowed parameters, opens, functors, record-field dispatch and higher-order flows. The Main.Client functor inputs are explicitly resolved to the supplied production client functions; the Service work_observer.run field is explicitly seeded from its production Telemetry.observe implementation. Abstract external callbacks, indirect factories not recognizable from this source pass, and parameter shadowing can still undercount or overcount. Thus 318/622 are a reproducible point estimate, not an exact minimum and not a defensible confidence interval. Their numeric precision records source sites, not certainty about the eventual API design. No repository was edited or built; only scratch copies were compiled.

## Logger variant comparison and standalone references

Both variants apply the same deferred-factory exclusions, count locals and three named partial bindings, and propagate resolved calls plus standalone references to fixed point. A standalone reference is a bare identifier occurrence denoting an io function passed/stored as a value, not the identifier serving as an application callee. The AST collector suppresses that callee reference, so references do not double-count application sites. Five inspected shadowing false positives (SQL query arguments, a decode callback parameter, and a BM25 result value) were explicitly removed. Other untyped-resolution limitations remain.

| Factory-adjusted census | Named functions | Application sites | Standalone io references |
|---|---:|---:|---:|
| Current synchronous journal/OTel reporters | **318** | **622** | **38** |
| Nonblocking Logger, bounded queue with try-add | **316** | **606** | **38** |
| Reduction | 2 | 16 | 0 |

The nonblocking variant assumes every Logger operation (including span begin/end emission) only performs a nonblocking try-add into a bounded queue, with overflow handled without waiting; one separate writer fiber drains the queue and performs mutex/flow/exporter I/O. This is a hypothetical design census, not an implementation or tested reporter. Logger callbacks can still suspend independently and need yielding callback modes. The observer wrappers become generic callback-mode helpers, not intrinsic io signatures; the two functions removed are Telemetry.observe and Service.observe_work. The HTTP handler still requires io through its partial Service.handler binding; construction of that binding itself does not execute the handler. Writer-fiber startup and shutdown retain their existing fork/drain io cost; no invented source sites for the hypothetical queue are added.

For this variant the publication on_waiting callback, whose work thunk is pure, no longer reaches suspending logging. That removes the identified logging violation, but does not turn other Eio-protected database waits into critical-section violations. Queue overflow/drop policy and log-delivery guarantees are separate design costs. Standalone-reference inventories are [io-references.json](</tmp/suspend-token-cost/nema/io-references.json>) and [nonblocking-io-references.json](</tmp/suspend-token-cost/nema/nonblocking-io-references.json>); variant counts/signatures/applications are [nonblocking-counts.json](</tmp/suspend-token-cost/nema/nonblocking-counts.json>), [nonblocking-io-signatures.json](</tmp/suspend-token-cost/nema/nonblocking-io-signatures.json>), and [nonblocking-io-calls.json](</tmp/suspend-token-cost/nema/nonblocking-io-calls.json>). The unchanged reference total records the remaining passed/stored io functions, not the eight logging calls.

## Per-module migration estimate

| Production implementation | Named signatures | io applications | Direct external roots |
|---|---:|---:|---:|
| [bin/nema/main.ml](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml>) | 41 | 75 | 21 |
| [bin/nema/telemetry.ml](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml>) | 2 | 3 | 3 |
| [lib/ladybug/nema_ladybug.ml](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml>) | 14 | 21 | 9 |
| [lib/nema/corpus_store.ml](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml>) | 30 | 44 | 0 |
| [lib/nema/cypher.ml](</home/ribelo/projects/ribelo/nema/lib/nema/cypher.ml>) | 2 | 4 | 0 |
| [lib/nema/db.ml](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml>) | 37 | 66 | 0 |
| [lib/nema/documents.ml](</home/ribelo/projects/ribelo/nema/lib/nema/documents.ml>) | 2 | 2 | 0 |
| [lib/nema/gate.ml](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml>) | 3 | 6 | 5 |
| [lib/nema/graph_query.ml](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml>) | 18 | 24 | 0 |
| [lib/nema/health.ml](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml>) | 5 | 11 | 0 |
| [lib/nema/http_api.ml](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml>) | 3 | 17 | 1 |
| [lib/nema/job_store.ml](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml>) | 29 | 29 | 1 |
| [lib/nema/lifecycle.ml](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml>) | 8 | 10 | 2 |
| [lib/nema/maintenance.ml](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml>) | 14 | 16 | 3 |
| [lib/nema/note.ml](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml>) | 10 | 12 | 0 |
| [lib/nema/query_embed.ml](</home/ribelo/projects/ribelo/nema/lib/nema/query_embed.ml>) | 4 | 7 | 3 |
| [lib/nema/search.ml](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml>) | 9 | 18 | 0 |
| [lib/nema/service.ml](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml>) | 64 | 229 | 13 |
| [lib/nema/vault.ml](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml>) | 11 | 12 | 4 |
| [lib/nema/watch_intake.ml](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml>) | 5 | 4 | 0 |
| [lib/nema/watcher.ml](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml>) | 7 | 12 | 0 |

Unlisted production modules have no discovered intrinsic/transitively resolved io signature. Pure generic callback helpers in those modules may still need mode changes.

## Critical sections and suspension locations

The inventory counts source sites, not disjoint runtime intervals: a wrapper definition, each wrapper invocation, and nested cancellation/mutex regions are separate rows. Suspensions are deduplicated by application position across those rows. The may-suspend count includes acquisitions and condition waits themselves. Actor handlers, Agent callbacks, Ox_app SERVICE.status callback implementations, short Ox.Mutex sections, and transport-mutex writes have **zero occurrences** in Nema production sources. Native C-state checks/transaction callbacks and Stdlib-mutex guards are must-not-suspend. Eio publication leases and protected drains are may-suspend.

### Verified violation

[gate.mli:19](</home/ribelo/projects/ribelo/nema/lib/nema/gate.mli#L19>) explicitly says on_waiting must not suspend. The supplied callback at [service.ml:738](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L738>) calls t.work_observer.run at line 739. Production wiring at [main.ml:1019](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1019>) invokes Telemetry.observe, which performs Logger.span at [telemetry.ml:85](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml#L85>) and Logger.info at [telemetry.ml:90](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml#L90>). The callback can therefore acquire the journal reporter mutex and perform flow I/O, and can enqueue OTel records. Move the notification outside the gate lock, or make this callback update pure state and emit telemetry afterward. Replacing an io argument without changing this callback is insufficient.

Configured reporters were checked, not blanket-excluded: [ox_app.ml:339](</home/ribelo/projects/ribelo/ocaml/ox/lib/app/ox_app.ml#L339>) creates Reporter.journal on Eio stderr; [logger.ml:114](</home/ribelo/projects/ribelo/ocaml/ox/lib/observability/logger.ml#L114>) emits under Eio.Mutex.use_ro and calls Eio.Flow.copy_string. [telemetry.ml:73](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml#L73>) installs Ox_otel.reporter unless OTEL_SDK_DISABLED is set; [ox_otel.ml:115](</home/ribelo/projects/ribelo/ocaml/ox/lib/otel/ox_otel.ml#L115>) submits via Eio.Stream.add. Journal locking/flow I/O is sufficient even if a particular OTel enqueue does not block.

The direct logging sites are main:984/985, telemetry:85/90, maintenance:44/45, and service:450/451. The eight direct sites are counted separately from the one indirect critical observer application; the two reachable Telemetry log sites are not added to the global eight again. Pure local status functions at [cli_error.ml:30](</home/ribelo/projects/ribelo/nema/bin/nema/cli_error.ml#L30>) and [watch_intake.ml:47](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L47>) remain must-not-suspend. The similarly named HTTP client functions at [main.ml:412](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L412>) and [main.ml:428](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L428>) perform HTTP requests and are ordinary io functions, not pure service-status callbacks.

### Every audited site

| Location | Policy | Site kind | Suspension application locations |
|---|---|---|---|
| [bin/nema/main.ml:910](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L910>) | may-suspend | cancellation protection (Eio.Cancel.protect) | None resolved in body; callback-only/guard or pure body |
| [bin/nema/main.ml:1146](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1146>) | may-suspend | cancellation protection (Eio.Cancel.protect) | Eio.Switch.run at 1146 |
| [lib/ladybug/nema_ladybug.ml:600](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L600>) | must-not-suspend | native C-state/transaction guard (if_database_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:612](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L612>) | must-not-suspend | native C-state/transaction guard (if_database_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:617](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L617>) | must-not-suspend | native C-state/transaction guard (if_connection_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:627](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L627>) | must-not-suspend | native C-state/transaction guard (if_connection_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:634](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L634>) | must-not-suspend | native C-state/transaction guard (if_connection_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:644](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L644>) | must-not-suspend | native C-state/transaction guard (if_connection_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:654](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L654>) | must-not-suspend | native C-state/transaction guard (if_connection_open) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:839](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L839>) | must-not-suspend | Stdlib mutex guard (Mutex.lock) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:842](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L842>) | must-not-suspend | Stdlib mutex guard (with_gate) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:843](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L843>) | must-not-suspend | Stdlib mutex guard (with_gate) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:847](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L847>) | must-not-suspend | Stdlib mutex guard (with_gate) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:1069](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1069>) | may-suspend | cancellation protection (Eio.Cancel.protect) | close at 1073 |
| [lib/ladybug/nema_ladybug.ml:1104](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1104>) | may-suspend | cancellation protection (Eio.Cancel.protect) | Eio.Mutex.use_rw at 1105; Eio.Semaphore.acquire at 1116; close_native at 1118 |
| [lib/ladybug/nema_ladybug.ml:1105](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1105>) | may-suspend | Eio mutex acquisition/body (Eio.Mutex.use_rw) | Eio.Mutex.use_rw at 1105; Eio.Semaphore.acquire at 1116; close_native at 1118 |
| [lib/ladybug/nema_ladybug.ml:1132](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1132>) | may-suspend | cancellation protection (Eio.Cancel.protect) | Ox_blocking.run_result at 1133 |
| [lib/nema/corpus_store.ml:1069](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1069>) | may-suspend | cancellation protection (Eio.Cancel.protect) | Db.execute at 1070 |
| [lib/nema/db.ml:146](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L146>) | may-suspend | cancellation protection (Eio.Cancel.protect) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/gate.ml:28](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L28>) | may-suspend | cancellation protection (Eio.Cancel.protect) | Eio.Mutex.use_ro at 29 |
| [lib/nema/gate.ml:29](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L29>) | may-suspend | Eio mutex acquisition/body (Eio.Mutex.use_ro) | Eio.Mutex.use_ro at 29 |
| [lib/nema/gate.ml:34](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L34>) | may-suspend | Eio mutex acquisition/body (Eio.Mutex.lock) | Eio.Mutex.lock at 34 |
| [lib/nema/gate.ml:39](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L39>) | may-suspend | cancellation protection (Eio.Cancel.protect) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/gate.ml:42](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L42>) | may-suspend | condition wait under mutex (Eio.Condition.await) | Eio.Condition.await at 42 |
| [lib/nema/gate.ml:50](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L50>) | may-suspend | Eio mutex acquisition/body (Eio.Mutex.lock) | Eio.Mutex.lock at 50 |
| [lib/nema/gate.ml:54](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L54>) | may-suspend | cancellation protection (Eio.Cancel.protect) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/gate.ml:63](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L63>) | may-suspend | condition wait under mutex (Eio.Condition.await) | Eio.Condition.await at 63 |
| [lib/nema/job_store.ml:36](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L36>) | may-suspend | Eio mutex acquisition/body (Eio.Mutex.lock) | Eio.Mutex.lock at 36 |
| [lib/nema/job_store.ml:78](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L78>) | may-suspend | Eio mutex acquisition/body (with_lock) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/job_store.ml:81](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L81>) | may-suspend | Eio mutex acquisition/body (with_lock) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/lifecycle.ml:327](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L327>) | may-suspend | cancellation protection (Eio.Cancel.protect) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/service.ml:104](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L104>) | may-suspend | exclusive Eio publication lease (Gate.with_write) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/service.ml:737](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L737>) | may-suspend | exclusive Eio publication lease (Gate.with_write) | publish_structural_plan at 744; Watch_intake.drain at 748; Watch_intake.validate_recovery at 752; publish_structural_plan at 756 |
| [lib/nema/service.ml:738](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L738>) | must-not-suspend | explicit on_waiting contract (Gate.with_write) | t.work_observer.run at 739 — **violation**, reaches Telemetry Logger.span:85 and Logger.info:90 |
| [lib/nema/service.ml:963](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L963>) | may-suspend | exclusive Eio publication lease (with_write_value) | publish_structural_plan at 963 |
| [lib/nema/service.ml:1246](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1246>) | may-suspend | exclusive Eio publication lease (Gate.with_write) | Corpus_store.verify_embedding_ready at 1250; Corpus_store.publish_embedding_state at 1255; Corpus_store.publish_embedding_state at 1266 |
| [lib/nema/service.ml:1282](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1282>) | may-suspend | exclusive Eio publication lease (Gate.with_write) | Corpus_store.materialize_cached_embeddings at 1283 |
| [lib/nema/service.ml:1368](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1368>) | may-suspend | exclusive Eio publication lease (Gate.with_write) | Corpus_store.publish_embedding_batch at 1372 |
| [lib/nema/service.ml:1488](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1488>) | may-suspend | exclusive Eio publication lease (with_write_value) | Corpus_store.read_meta at 1493; Corpus_store.embedding_coverage at 1503; Corpus_store.verify_embedding_ready at 1510; Corpus_store.publish_embedding_state at 1518; Maintenance.complete at 1526 |
| [lib/nema/service.ml:1799](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1799>) | may-suspend | exclusive Eio publication lease (with_write_value) | persist_rebuild_mutation_started at 1802; rebuild_schema_in_place at 1806; publish_structural_plan at 1808 |
| [lib/nema/vault.ml:67](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L67>) | must-not-suspend | Stdlib mutex guard (Mutex.lock) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:200](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L200>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:218](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L218>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:223](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L223>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:283](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L283>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:286](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L286>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:295](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L295>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:300](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L300>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:315](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L315>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:332](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L332>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/vault.ml:337](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L337>) | may-suspend | cancellation protection (Eio.Cancel.protect) | Ox_blocking.Pool.shutdown at 339; Ox_blocking.Pool.shutdown at 340 |
| [lib/nema/vault.ml:341](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L341>) | must-not-suspend | Stdlib mutex guard (locked) | None resolved in body; callback-only/guard or pure body |
| [lib/ladybug/nema_ladybug.ml:716](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L716>) | must-not-suspend | native transaction callback contract (transaction) | None resolved in body; callback-only/guard or pure body |
| [lib/nema/watch_intake.ml:47](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L47>) | must-not-suspend | pure status query (status) | None resolved in body; callback-only/guard or pure body |

Important legitimate waits are the Gate reader/writer condition waits at [gate.ml:42](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L42>) and [gate.ml:63](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L63>), the Owner close semaphore drain at [nema_ladybug.ml:1116](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1116>), and admitted database operations in Service write leases. Gate’s writer f is not declared must-not-suspend; only on_waiting is. Marking all Eio-mutex-held writer work unyielding would outlaw intentional production database waits and exaggerate violations.

## Generic callback-mode changes (not io signatures)

Pure bind/map/iteration helpers do not need an io parameter just because a caller supplies a suspending continuation. Result bind and iter_exit need **yielding callback modes**, e.g. f : _ @ local once yielding. Native/Stdlib guard helpers instead need **local unyielding** callback modes. Library List/Option/Result iteration APIs outside Nema are not charged as Nema signatures. The following 85 named helpers are separate from the 318 affected io signatures; this is a migration-relevant list, not an assertion that every pure parser callback elsewhere must change.

| Helper | Location | Required treatment |
|---|---|---|
| Main.let* | [main.ml:937](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L937>) | pure result bind; yielding callback mode only |
| Main.Door_config.let* | [main.ml:1171](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1171>) | pure result bind; yielding callback mode only |
| Collection_page.let* | [collection_page.ml:64](</home/ribelo/projects/ribelo/nema/lib/nema/collection_page.ml#L64>) | pure result bind; yielding callback mode only |
| Config.let* | [config.ml:189](</home/ribelo/projects/ribelo/nema/lib/nema/config.ml#L189>) | pure result bind; yielding callback mode only |
| Config.let* | [config.ml:202](</home/ribelo/projects/ribelo/nema/lib/nema/config.ml#L202>) | pure result bind; yielding callback mode only |
| Config.let* | [config.ml:224](</home/ribelo/projects/ribelo/nema/lib/nema/config.ml#L224>) | pure result bind; yielding callback mode only |
| Corpus_store.Session.let* | [corpus_store.ml:299](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L299>) | pure result bind; yielding callback mode only |
| Corpus_store.let* | [corpus_store.ml:641](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L641>) | pure result bind; yielding callback mode only |
| Corpus_store.let* | [corpus_store.ml:1001](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1001>) | pure result bind; yielding callback mode only |
| Corpus_store.let* | [corpus_store.ml:1020](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1020>) | pure result bind; yielding callback mode only |
| Corpus_store.let* | [corpus_store.ml:1235](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1235>) | pure result bind; yielding callback mode only |
| Db.let* | [db.ml:161](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L161>) | pure result bind; yielding callback mode only |
| Db.let* | [db.ml:244](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L244>) | pure result bind; yielding callback mode only |
| Exit_result.let* | [exit_result.ml:1](</home/ribelo/projects/ribelo/nema/lib/nema/exit_result.ml#L1>) | pure result bind; yielding callback mode only |
| Filter.let* | [filter.ml:221](</home/ribelo/projects/ribelo/nema/lib/nema/filter.ml#L221>) | pure result bind; yielding callback mode only |
| Filter.let* | [filter.ml:255](</home/ribelo/projects/ribelo/nema/lib/nema/filter.ml#L255>) | pure result bind; yielding callback mode only |
| Filter.let* | [filter.ml:286](</home/ribelo/projects/ribelo/nema/lib/nema/filter.ml#L286>) | pure result bind; yielding callback mode only |
| Graph_query.let* | [graph_query.ml:842](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L842>) | pure result bind; yielding callback mode only |
| Http_api.let* | [http_api.ml:61](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L61>) | pure result bind; yielding callback mode only |
| Http_api.let* | [http_api.ml:104](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L104>) | pure result bind; yielding callback mode only |
| Http_api.let* | [http_api.ml:125](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L125>) | pure result bind; yielding callback mode only |
| Http_api.let* | [http_api.ml:162](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L162>) | pure result bind; yielding callback mode only |
| Http_api.let* | [http_api.ml:171](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L171>) | pure result bind; yielding callback mode only |
| Http_api.let* | [http_api.ml:185](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L185>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:82](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L82>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:144](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L144>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:152](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L152>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:167](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L167>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:185](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L185>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:200](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L200>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:215](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L215>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:227](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L227>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:238](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L238>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:250](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L250>) | pure result bind; yielding callback mode only |
| Job_store.let* | [job_store.ml:262](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L262>) | pure result bind; yielding callback mode only |
| Lifecycle.let* | [lifecycle.ml:52](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L52>) | pure result bind; yielding callback mode only |
| Lifecycle.let* | [lifecycle.ml:273](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L273>) | pure result bind; yielding callback mode only |
| Lifecycle.let* | [lifecycle.ml:311](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L311>) | pure result bind; yielding callback mode only |
| Lifecycle.let* | [lifecycle.ml:351](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L351>) | pure result bind; yielding callback mode only |
| Lifecycle.let* | [lifecycle.ml:403](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L403>) | pure result bind; yielding callback mode only |
| Lifecycle.let* | [lifecycle.ml:460](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L460>) | pure result bind; yielding callback mode only |
| Note.let* | [note.ml:68](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L68>) | pure result bind; yielding callback mode only |
| Note.let* | [note.ml:106](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L106>) | pure result bind; yielding callback mode only |
| Note.let* | [note.ml:214](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L214>) | pure result bind; yielding callback mode only |
| Response_contract.let* | [response_contract.ml:3](</home/ribelo/projects/ribelo/nema/lib/nema/response_contract.ml#L3>) | pure result bind; yielding callback mode only |
| Search.let* | [search.ml:322](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L322>) | pure result bind; yielding callback mode only |
| Service.let* | [service.ml:3](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L3>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:398](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L398>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:417](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L417>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:469](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L469>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:504](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L504>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:579](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L579>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:648](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L648>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:688](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L688>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:710](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L710>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:722](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L722>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:733](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L733>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:765](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L765>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:778](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L778>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:951](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L951>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:957](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L957>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:992](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L992>) | pure result bind; yielding callback mode only |
| Service_state.let* | [service_state.ml:1034](</home/ribelo/projects/ribelo/nema/lib/nema/service_state.ml#L1034>) | pure result bind; yielding callback mode only |
| Corpus_store.Session.let* | [corpus_store.ml:115](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L115>) | pure result bind; yielding callback mode only |
| Corpus_store.let* | [corpus_store.ml:522](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L522>) | pure result bind; yielding callback mode only |
| Documents.let* | [documents.ml:24](</home/ribelo/projects/ribelo/nema/lib/nema/documents.ml#L24>) | pure result bind; yielding callback mode only |
| Graph_query.let* | [graph_query.ml:15](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L15>) | pure result bind; yielding callback mode only |
| Health.let* | [health.ml:1](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml#L1>) | pure result bind; yielding callback mode only |
| Note.let* | [note.ml:28](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L28>) | pure result bind; yielding callback mode only |
| Search.let* | [search.ml:78](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L78>) | pure result bind; yielding callback mode only |
| Exit_result.iter_exit | [exit_result.ml:3](</home/ribelo/projects/ribelo/nema/lib/nema/exit_result.ml#L3>) | generic result iteration |
| Db.resolve_endpoint_index_with | [db.ml:988](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L988>) | pure algorithm parameterized by query_rows; yielding callback mode |
| Vault.with_verified_directory | [vault.ml:92](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L92>) | pure/native descriptor lifetime wrapper; callback mode, unyielding when called under locked |
| Vault.with_directory_path | [vault.ml:206](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L206>) | pure/native directory validation wrapper; callback mode, native callers remain unyielding |
| Vault.inspection_parent | [vault.ml:233](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L233>) | pure/native validation wrapper; callback mode, unyielding when called under locked |
| Db.with_cleanup | [db.ml:145](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L145>) | generic protected cleanup/body; no intrinsic suspension |
| Vault.with_revision | [vault.ml:51](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L51>) | pure revision guard; callback mode |
| Vault.protect | [vault.ml:63](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L63>) | pure exception-to-result wrapper; callback mode |
| Vault.locked | [vault.ml:67](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L67>) | Stdlib-mutex callback must be local unyielding, not yielding |
| Nema_ladybug.wrap | [nema_ladybug.ml:513](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L513>) | pure error wrapper; native callers may choose unyielding |
| Nema_ladybug.if_database_open | [nema_ladybug.ml:527](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L527>) | native state callback must be local unyielding |
| Nema_ladybug.if_connection_open | [nema_ladybug.ml:529](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L529>) | native state callback must be local unyielding |
| Nema_ladybug.Owner.with_gate | [nema_ladybug.ml:838](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L838>) | Stdlib-mutex callback must be local unyielding |
| Nema_ladybug.Owner.statement | [nema_ladybug.ml:1171](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1171>) | pure statement validation; yielding continuation |
| Main.with_service | [main.ml:196](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L196>) | pure configuration wrapper around yielding callback |

## Compiled real-module prototype

The prototype is the real 65-line [Gate implementation](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L1>), not a toy replacement. The original shared/read lease, writer preference, cleanup-before-wait ordering, Eio cancellation protection, and condition relock semantics remain. Its 19-line [interface](</home/ribelo/projects/ribelo/nema/lib/nema/gate.mli#L1>) keeps the original documentation. The migrated private release_read and public with_read/with_write receive io; create stays pure. The on_waiting callback and the short reader-count mutation callback are local unyielding; the reader and writer work callbacks are local once yielding.

Artifacts: [io.ml](</tmp/suspend-token-cost/nema/io.ml>), [shim.ml](</tmp/suspend-token-cost/nema/shim.ml>), [gate.ml](</tmp/suspend-token-cost/nema/gate.ml>), [gate.mli](</tmp/suspend-token-cost/nema/gate.mli>), [positive.ml](</tmp/suspend-token-cost/nema/positive.ml>), [negative.ml](</tmp/suspend-token-cost/nema/negative.ml>).

### Token and explicit continuation

~~~ocaml
type io = { suspend : unit -> unit } [@@unboxed]
type t = io

let bind r (f : ('a -> ('b, 'e) result) @ local once yielding) =
  match r with Ok value -> f value | Error error -> Error error
~~~

Representative before, from [gate.ml:49](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L49>):

~~~ocaml
let with_write ?(on_waiting = fun () -> Ok ()) t f =
  Eio.Mutex.lock t.mutex;
  (* existing writer count and protected cleanup *)
  match if t.active_readers > 0 then on_waiting () else Ok () with
  | Error cause -> Error cause
  | Ok () ->
      while t.active_readers > 0 do
        Eio.Condition.await t.cond t.mutex
      done;
      f ()
~~~

Representative after, from [gate.ml](</tmp/suspend-token-cost/nema/gate.ml>):

~~~ocaml
let with_write ~(io : Io.t @ yielding)
    ?(on_waiting : (unit -> (unit, 'e) result) @ local unyielding =
      fun () -> Ok ()) t
    (f : (unit -> ('a, 'e) result) @ local once yielding) =
  Shim.mutex_lock ~io t.mutex;
  (* original writer count and protected cleanup remain *)
  let r = if t.active_readers > 0 then on_waiting () else Ok () in
  Shim.bind r (fun () ->
      while t.active_readers > 0 do
        Shim.condition_await ~io t.cond t.mutex
      done;
      f ()) [@nontail]
~~~

The full implementation additionally marks the enclosing protect application non-tail. This is required for local callbacks: the first compile correctly rejected a local f captured by a closure passed in a tail call. The explicit bind continuation carries local-once-yielding callback modes instead of relying on legacy Result.bind/let* modes.

### Pinned command and results

~~~sh
cd /home/ribelo/projects/ribelo/ocaml/ox
nix develop -c sh -c 'cd /tmp/suspend-token-cost/nema && ocamlfind ocamlopt -package eio -c io.ml shim.ml gate.mli gate.ml'
nix develop -c sh -c 'cd /tmp/suspend-token-cost/nema && ocamlfind ocamlopt -package eio_main -linkpkg io.cmx shim.cmx gate.cmx positive.ml -o positive && ./positive && ocamlc -version'
nix develop -c sh -c 'cd /tmp/suspend-token-cost/nema && ocamlfind ocamlopt -package eio -c negative.ml'
~~~

Compile and positive runtime result: **exit 0**, compiler **5.4.0+ox**, output “positive: reader/writer suspension and explicit bind passed”. See [compile-positive.log](</tmp/suspend-token-cost/nema/compile-positive.log>). Negative control: **exit 2**, the intended rejection:

~~~text
Error: The value io is yielding
       but is expected to be unyielding
         because it is used inside the function ...
         which is expected to be unyielding.
~~~

The rejected callback calls Shim.yield ~io from on_waiting. See [compile-negative.log](</tmp/suspend-token-cost/nema/compile-negative.log>). The positive test executes Eio yielding reader and writer callbacks and an explicit bind; it is a smoke test, not a cancellation/contention regression suite.

### Trusted shim and evidence boundary

[shim.ml](</tmp/suspend-token-cost/nema/shim.ml>) is a separate legacy-Eio adaptation boundary. Its external %identity legacy_callback representation cast converts a local once yielding callback to the old global/many callback type **only for immediate, synchronous** Eio.Cancel.protect and Eio.Mutex.use_ro invocation. This is a trusted, unsafe compatibility shim, not a generally sound conversion or evidence that upstream Eio types already implement yielding modes. The manual protect preserves single callback invocation and exception backtraces. Eio locks/waits/cancellation remain real Eio calls, not no-op stubs; Io.touch uses a no-op hook in the smoke-test token. Compiler enforcement is proven at the migrated Gate API and negative control, not across an unmodified Eio ecosystem or publicly mintable token representation.

### Lines touched / module size

| File | Original lines | Prototype lines | Original lines replaced/deleted | New lines inserted/replaced |
|---|---:|---:|---:|---:|
| [gate.ml](</tmp/suspend-token-cost/nema/gate.ml>) | 65 | 68 | 19 | 22 |
| [gate.mli](</tmp/suspend-token-cost/nema/gate.mli>) | 19 | 22 | 3 | 6 |

Implementation: **19/65 original lines touched (29.2%)**, 22 new/replacement lines, net +3 lines. Interface: **3/19 original lines touched (15.8%)**, 6 new/replacement lines, net +3. The combined 84-line module/interface touches 22 original lines (26.2%), net +6. Supporting shim/token lines are separate; they are one-time compatibility scaffolding, not charged to Gate or extrapolated to all 27.798 kloc. Exact diffs: [gate.ml.diff](</tmp/suspend-token-cost/nema/gate.ml.diff>) and [gate.mli.diff](</tmp/suspend-token-cost/nema/gate.mli.diff>).

## Complete affected named-signature inventory

The 318 rows below are the adjusted point estimate. Each has application/reference reasons in [io-signatures.json](</tmp/suspend-token-cost/nema/io-signatures.json>); [io-calls.json](</tmp/suspend-token-cost/nema/io-calls.json>) contains all 622 adjusted application positions. The raw 323-row inventory is [raw-io-signatures.json](</tmp/suspend-token-cost/nema/raw-io-signatures.json>). Source definition position distinguishes identically named locals.

| Named signature | Definition |
|---|---|
| Main.http_request | [bin/nema/main.ml:103](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L103>) |
| Main.http_post_allow_error | [bin/nema/main.ml:133](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L133>) |
| Main.http_get_allow_error | [bin/nema/main.ml:136](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L136>) |
| Main.get_health | [bin/nema/main.ml:139](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L139>) |
| Main.client_post | [bin/nema/main.ml:204](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L204>) |
| Main.client_get | [bin/nema/main.ml:212](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L212>) |
| Main.Client.run | [bin/nema/main.ml:397](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L397>) |
| Main.Client.default | [bin/nema/main.ml:411](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L411>) |
| Main.Client.status | [bin/nema/main.ml:412](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L412>) |
| Main.Client.default | [bin/nema/main.ml:427](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L427>) |
| Main.Client.status | [bin/nema/main.ml:428](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L428>) |
| Main.Client.run | [bin/nema/main.ml:480](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L480>) |
| Main.Client.run | [bin/nema/main.ml:493](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L493>) |
| Main.Client.run | [bin/nema/main.ml:506](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L506>) |
| Main.Client.collection_post | [bin/nema/main.ml:526](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L526>) |
| Main.Client.run | [bin/nema/main.ml:535](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L535>) |
| Main.Client.run | [bin/nema/main.ml:578](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L578>) |
| Main.Client.run | [bin/nema/main.ml:607](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L607>) |
| Main.Client.run | [bin/nema/main.ml:621](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L621>) |
| Main.Client.run | [bin/nema/main.ml:639](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L639>) |
| Main.Client.run | [bin/nema/main.ml:649](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L649>) |
| Main.Client.run | [bin/nema/main.ml:665](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L665>) |
| Main.Client.run | [bin/nema/main.ml:675](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L675>) |
| Main.Client.run | [bin/nema/main.ml:684](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L684>) |
| Main.Client.run | [bin/nema/main.ml:693](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L693>) |
| Main.Client.run | [bin/nema/main.ml:703](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L703>) |
| Main.run (local) | [bin/nema/main.ml:755](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L755>) |
| Main.run (local) | [bin/nema/main.ml:779](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L779>) |
| Main.run (local) | [bin/nema/main.ml:808](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L808>) |
| Main.run (local) | [bin/nema/main.ml:840](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L840>) |
| Main.on_release | [bin/nema/main.ml:908](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L908>) |
| Main.serve | [bin/nema/main.ml:935](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L935>) |
| Main.until_interrupted (local) | [bin/nema/main.ml:960](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L960>) |
| Main.body (local) | [bin/nema/main.ml:977](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L977>) |
| Main.handler (local) | [bin/nema/main.ml:1058](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1058>) |
| Main.startup (local) | [bin/nema/main.ml:1087](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1087>) |
| Main.run (local) | [bin/nema/main.ml:1135](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1135>) |
| Main.Door_config.read_file | [bin/nema/main.ml:1288](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1288>) |
| Telemetry.acquire | [bin/nema/telemetry.ml:48](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml#L48>) |
| Telemetry.observe | [bin/nema/telemetry.ml:82](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml#L82>) |
| Nema_ladybug.Owner.acquire | [lib/ladybug/nema_ladybug.ml:972](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L972>) |
| Nema_ladybug.Owner.admit | [lib/ladybug/nema_ladybug.ml:1009](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1009>) |
| Nema_ladybug.Owner.run | [lib/ladybug/nema_ladybug.ml:1050](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1050>) |
| Nema_ladybug.Owner.attempt (local) | [lib/ladybug/nema_ladybug.ml:1051](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1051>) |
| Nema_ladybug.Owner.register_release | [lib/ladybug/nema_ladybug.ml:1067](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1067>) |
| Nema_ladybug.Owner.close_native | [lib/ladybug/nema_ladybug.ml:1077](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1077>) |
| Nema_ladybug.Owner.close | [lib/ladybug/nema_ladybug.ml:1103](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1103>) |
| Nema_ladybug.Owner.open_ | [lib/ladybug/nema_ladybug.ml:1122](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1122>) |
| Nema_ladybug.Owner.classify_read_only | [lib/ladybug/nema_ladybug.ml:1225](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1225>) |
| Nema_ladybug.Owner.query_string | [lib/ladybug/nema_ladybug.ml:1230](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1230>) |
| Nema_ladybug.Owner.query_rows | [lib/ladybug/nema_ladybug.ml:1237](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1237>) |
| Nema_ladybug.Owner.query | [lib/ladybug/nema_ladybug.ml:1244](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1244>) |
| Nema_ladybug.Owner.execute | [lib/ladybug/nema_ladybug.ml:1251](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1251>) |
| Nema_ladybug.Owner.transaction | [lib/ladybug/nema_ladybug.ml:1327](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1327>) |
| Corpus_store.query | [lib/nema/corpus_store.ml:528](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L528>) |
| Corpus_store.check_ownership | [lib/nema/corpus_store.ml:530](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L530>) |
| Corpus_store.check (local) | [lib/nema/corpus_store.ml:539](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L539>) |
| Corpus_store.read_document_hashes_now | [lib/nema/corpus_store.ml:570](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L570>) |
| Corpus_store.read_document_sources_now | [lib/nema/corpus_store.ml:583](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L583>) |
| Corpus_store.load_resolve_index_now | [lib/nema/corpus_store.ml:663](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L663>) |
| Corpus_store.read_document_hashes | [lib/nema/corpus_store.ml:667](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L667>) |
| Corpus_store.read_document_sources | [lib/nema/corpus_store.ml:670](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L670>) |
| Corpus_store.load_resolve_index | [lib/nema/corpus_store.ml:673](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L673>) |
| Corpus_store.load_resolve_index_session | [lib/nema/corpus_store.ml:695](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L695>) |
| Corpus_store.resolve_all_references | [lib/nema/corpus_store.ml:706](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L706>) |
| Corpus_store.read_generation | [lib/nema/corpus_store.ml:809](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L809>) |
| Corpus_store.read_generation_session | [lib/nema/corpus_store.ml:813](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L813>) |
| Corpus_store.publish_embedding_state_now | [lib/nema/corpus_store.ml:838](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L838>) |
| Corpus_store.publish_embedding_state | [lib/nema/corpus_store.ml:856](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L856>) |
| Corpus_store.read_meta | [lib/nema/corpus_store.ml:859](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L859>) |
| Corpus_store.embedding_coverage | [lib/nema/corpus_store.ml:907](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L907>) |
| Corpus_store.verify_embedding_ready_now | [lib/nema/corpus_store.ml:935](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L935>) |
| Corpus_store.missing_embedding_rows | [lib/nema/corpus_store.ml:979](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L979>) |
| Corpus_store.publish_with_transaction | [lib/nema/corpus_store.ml:1041](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1041>) |
| Corpus_store.publish_structural | [lib/nema/corpus_store.ml:1080](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1080>) |
| Corpus_store.materialize_cached_embeddings_now | [lib/nema/corpus_store.ml:1112](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1112>) |
| Corpus_store.materialize_cached_embeddings | [lib/nema/corpus_store.ml:1210](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1210>) |
| Corpus_store.pending_embeddings_now | [lib/nema/corpus_store.ml:1213](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1213>) |
| Corpus_store.queued_embedding_demand_now | [lib/nema/corpus_store.ml:1218](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1218>) |
| Corpus_store.verify_embedding_ready | [lib/nema/corpus_store.ml:1222](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1222>) |
| Corpus_store.pending_embeddings | [lib/nema/corpus_store.ml:1225](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1225>) |
| Corpus_store.queued_embedding_demand | [lib/nema/corpus_store.ml:1228](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1228>) |
| Corpus_store.publish_embeddings | [lib/nema/corpus_store.ml:1231](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1231>) |
| Corpus_store.publish_embedding_batch | [lib/nema/corpus_store.ml:1332](</home/ribelo/projects/ribelo/nema/lib/nema/corpus_store.ml#L1332>) |
| Cypher.encode_result | [lib/nema/cypher.ml:56](</home/ribelo/projects/ribelo/nema/lib/nema/cypher.ml#L56>) |
| Cypher.query | [lib/nema/cypher.ml:84](</home/ribelo/projects/ribelo/nema/lib/nema/cypher.ml#L84>) |
| Db.query | [lib/nema/db.ml:70](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L70>) |
| Db.query_rows | [lib/nema/db.ml:74](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L74>) |
| Db.query_string | [lib/nema/db.ml:78](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L78>) |
| Db.execute | [lib/nema/db.ml:82](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L82>) |
| Db.classify_read_only | [lib/nema/db.ml:86](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L86>) |
| Db.close | [lib/nema/db.ml:90](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L90>) |
| Db.transaction | [lib/nema/db.ml:126](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L126>) |
| Db.connect_database | [lib/nema/db.ml:163](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L163>) |
| Db.ensure_extensions | [lib/nema/db.ml:169](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L169>) |
| Db.loop (local) | [lib/nema/db.ml:174](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L174>) |
| Db.checkpoint | [lib/nema/db.ml:187](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L187>) |
| Db.with_checkpoint_on_commit | [lib/nema/db.ml:189](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L189>) |
| Db.ensure_schema_extensions | [lib/nema/db.ml:194](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L194>) |
| Db.exec_bootstrap | [lib/nema/db.ml:197](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L197>) |
| Db.run (local) | [lib/nema/db.ml:198](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L198>) |
| Db.insert_meta | [lib/nema/db.ml:219](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L219>) |
| Db.bootstrap | [lib/nema/db.ml:227](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L227>) |
| Db.run (local) | [lib/nema/db.ml:228](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L228>) |
| Db.catalog_tables | [lib/nema/db.ml:239](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L239>) |
| Db.catalog_strings | [lib/nema/db.ml:252](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L252>) |
| Db.catalog_indexes | [lib/nema/db.ml:274](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L274>) |
| Db.catalog_columns | [lib/nema/db.ml:319](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L319>) |
| Db.catalog_connection | [lib/nema/db.ml:340](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L340>) |
| Db.physical_schema_error | [lib/nema/db.ml:363](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L363>) |
| Db.validate (local) | [lib/nema/db.ml:366](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L366>) |
| Db.validate_columns (local) | [lib/nema/db.ml:380](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L380>) |
| Db.check_nodes (local) | [lib/nema/db.ml:394](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L394>) |
| Db.check_relationships (local) | [lib/nema/db.ml:411](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L411>) |
| Db.rebuild_schema_in_place | [lib/nema/db.ml:461](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L461>) |
| Db.drop (local) | [lib/nema/db.ml:512](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L512>) |
| Db.initialize | [lib/nema/db.ml:522](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L522>) |
| Db.open_fresh | [lib/nema/db.ml:530](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L530>) |
| Db.read_meta | [lib/nema/db.ml:540](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L540>) |
| Db.open_existing | [lib/nema/db.ml:557](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L557>) |
| Db.resolve_endpoint_index_with | [lib/nema/db.ml:988](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L988>) |
| Db.load (local) | [lib/nema/db.ml:1062](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L1062>) |
| Db.resolve_endpoint_index | [lib/nema/db.ml:1118](</home/ribelo/projects/ribelo/nema/lib/nema/db.ml#L1118>) |
| Documents.list_now | [lib/nema/documents.ml:41](</home/ribelo/projects/ribelo/nema/lib/nema/documents.ml#L41>) |
| Documents.list | [lib/nema/documents.ml:82](</home/ribelo/projects/ribelo/nema/lib/nema/documents.ml#L82>) |
| Gate.release_read | [lib/nema/gate.ml:27](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L27>) |
| Gate.with_read | [lib/nema/gate.ml:33](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L33>) |
| Gate.with_write | [lib/nema/gate.ml:49](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L49>) |
| Graph_query.links_now | [lib/nema/graph_query.ml:195](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L195>) |
| Graph_query.run_backlinks_query | [lib/nema/graph_query.ml:314](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L314>) |
| Graph_query.require_block_now | [lib/nema/graph_query.ml:371](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L371>) |
| Graph_query.find_section_id_now | [lib/nema/graph_query.ml:397](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L397>) |
| Graph_query.backlinks_now | [lib/nema/graph_query.ml:423](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L423>) |
| Graph_query.tagged_now | [lib/nema/graph_query.ml:459](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L459>) |
| Graph_query.orphans_now | [lib/nema/graph_query.ml:499](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L499>) |
| Graph_query.neighborhood_now | [lib/nema/graph_query.ml:556](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L556>) |
| Graph_query.walk (local) | [lib/nema/graph_query.ml:572](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L572>) |
| Graph_query.links | [lib/nema/graph_query.ml:681](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L681>) |
| Graph_query.backlinks | [lib/nema/graph_query.ml:684](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L684>) |
| Graph_query.tagged | [lib/nema/graph_query.ml:687](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L687>) |
| Graph_query.orphans | [lib/nema/graph_query.ml:690](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L690>) |
| Graph_query.neighborhood | [lib/nema/graph_query.ml:693](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L693>) |
| Graph_query.tags_now | [lib/nema/graph_query.ml:696](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L696>) |
| Graph_query.unresolved_now | [lib/nema/graph_query.ml:799](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L799>) |
| Graph_query.tags | [lib/nema/graph_query.ml:906](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L906>) |
| Graph_query.unresolved | [lib/nema/graph_query.ml:909](</home/ribelo/projects/ribelo/nema/lib/nema/graph_query.ml#L909>) |
| Health.observed_document_count | [lib/nema/health.ml:86](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml#L86>) |
| Health.observe_now | [lib/nema/health.ml:107](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml#L107>) |
| Health.collect_now | [lib/nema/health.ml:293](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml#L293>) |
| Health.observe | [lib/nema/health.ml:466](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml#L466>) |
| Health.collect | [lib/nema/health.ml:469](</home/ribelo/projects/ribelo/nema/lib/nema/health.ml#L469>) |
| Http_api.parse_json_body | [lib/nema/http_api.ml:41](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L41>) |
| Http_api.with_json_body | [lib/nema/http_api.ml:52](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L52>) |
| Http_api.decode | [lib/nema/http_api.ml:135](</home/ribelo/projects/ribelo/nema/lib/nema/http_api.ml#L135>) |
| Job_store.with_lock | [lib/nema/job_store.ml:35](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L35>) |
| Job_store.read_now | [lib/nema/job_store.ml:78](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L78>) |
| Job_store.transact_now | [lib/nema/job_store.ml:80](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L80>) |
| Job_store.accept_now | [lib/nema/job_store.ml:106](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L106>) |
| Job_store.accept_recovery_now | [lib/nema/job_store.ml:119](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L119>) |
| Job_store.find_job_now | [lib/nema/job_store.ml:132](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L132>) |
| Job_store.active_job_now | [lib/nema/job_store.ml:137](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L137>) |
| Job_store.next_job_now | [lib/nema/job_store.ml:140](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L140>) |
| Job_store.start_now | [lib/nema/job_store.ml:142](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L142>) |
| Job_store.checkpoint_with_now | [lib/nema/job_store.ml:150](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L150>) |
| Job_store.checkpoint_running_sync_with_now | [lib/nema/job_store.ml:163](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L163>) |
| Job_store.set_sync_retry_now | [lib/nema/job_store.ml:181](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L181>) |
| Job_store.clear_sync_retry_now | [lib/nema/job_store.ml:209](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L209>) |
| Job_store.mark_rebuild_mutation_started_now | [lib/nema/job_store.ml:236](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L236>) |
| Job_store.complete_now | [lib/nema/job_store.ml:248](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L248>) |
| Job_store.fail_now | [lib/nema/job_store.ml:260](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L260>) |
| Job_store.accept | [lib/nema/job_store.ml:274](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L274>) |
| Job_store.accept_recovery | [lib/nema/job_store.ml:277](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L277>) |
| Job_store.find_job | [lib/nema/job_store.ml:280](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L280>) |
| Job_store.active_job | [lib/nema/job_store.ml:283](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L283>) |
| Job_store.next_job | [lib/nema/job_store.ml:286](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L286>) |
| Job_store.start | [lib/nema/job_store.ml:288](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L288>) |
| Job_store.checkpoint_with | [lib/nema/job_store.ml:291](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L291>) |
| Job_store.checkpoint_running_sync_with | [lib/nema/job_store.ml:295](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L295>) |
| Job_store.set_sync_retry | [lib/nema/job_store.ml:299](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L299>) |
| Job_store.clear_sync_retry | [lib/nema/job_store.ml:302](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L302>) |
| Job_store.mark_rebuild_mutation_started | [lib/nema/job_store.ml:305](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L305>) |
| Job_store.complete | [lib/nema/job_store.ml:309](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L309>) |
| Job_store.fail | [lib/nema/job_store.ml:313](</home/ribelo/projects/ribelo/nema/lib/nema/job_store.ml#L313>) |
| Lifecycle.open_database | [lib/nema/lifecycle.ml:79](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L79>) |
| Lifecycle.close_database | [lib/nema/lifecycle.ml:83](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L83>) |
| Lifecycle.wait_for_ready_instance | [lib/nema/lifecycle.ml:244](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L244>) |
| Lifecycle.loop (local) | [lib/nema/lifecycle.ml:246](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L246>) |
| Lifecycle.start_daemon | [lib/nema/lifecycle.ml:310](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L310>) |
| Lifecycle.wait_for_stop_release | [lib/nema/lifecycle.ml:439](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L439>) |
| Lifecycle.loop (local) | [lib/nema/lifecycle.ml:442](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L442>) |
| Lifecycle.stop_registered | [lib/nema/lifecycle.ml:459](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L459>) |
| Maintenance.wait_for_signal | [lib/nema/maintenance.ml:19](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L19>) |
| Maintenance.accept | [lib/nema/maintenance.ml:23](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L23>) |
| Maintenance.accept_recovery | [lib/nema/maintenance.ml:24](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L24>) |
| Maintenance.find_job | [lib/nema/maintenance.ml:26](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L26>) |
| Maintenance.active_job | [lib/nema/maintenance.ml:27](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L27>) |
| Maintenance.next_job | [lib/nema/maintenance.ml:28](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L28>) |
| Maintenance.start | [lib/nema/maintenance.ml:29](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L29>) |
| Maintenance.checkpoint_with | [lib/nema/maintenance.ml:30](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L30>) |
| Maintenance.checkpoint_running_sync_with | [lib/nema/maintenance.ml:31](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L31>) |
| Maintenance.set_sync_retry | [lib/nema/maintenance.ml:32](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L32>) |
| Maintenance.clear_sync_retry | [lib/nema/maintenance.ml:33](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L33>) |
| Maintenance.mark_rebuild_mutation_started | [lib/nema/maintenance.ml:34](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L34>) |
| Maintenance.complete | [lib/nema/maintenance.ml:35](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L35>) |
| Maintenance.fail | [lib/nema/maintenance.ml:37](</home/ribelo/projects/ribelo/nema/lib/nema/maintenance.ml#L37>) |
| Note.load_index | [lib/nema/note.ml:89](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L89>) |
| Note.show_with_index_now | [lib/nema/note.ml:195](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L195>) |
| Note.identity_with_index_now | [lib/nema/note.ml:229](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L229>) |
| Note.identity_with_index | [lib/nema/note.ml:252](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L252>) |
| Note.show_now | [lib/nema/note.ml:255](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L255>) |
| Note.find_fragment_now | [lib/nema/note.ml:286](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L286>) |
| Note.show_fragment_now | [lib/nema/note.ml:319](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L319>) |
| Note.show_fragment | [lib/nema/note.ml:367](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L367>) |
| Note.show_with_index | [lib/nema/note.ml:386](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L386>) |
| Note.show | [lib/nema/note.ml:389](</home/ribelo/projects/ribelo/nema/lib/nema/note.ml#L389>) |
| Query_embed.run_request | [lib/nema/query_embed.ml:103](</home/ribelo/projects/ribelo/nema/lib/nema/query_embed.ml#L103>) |
| Query_embed.attempt (local) | [lib/nema/query_embed.ml:105](</home/ribelo/projects/ribelo/nema/lib/nema/query_embed.ml#L105>) |
| Query_embed.embed | [lib/nema/query_embed.ml:128](</home/ribelo/projects/ribelo/nema/lib/nema/query_embed.ml#L128>) |
| Query_embed.embed_many | [lib/nema/query_embed.ml:138](</home/ribelo/projects/ribelo/nema/lib/nema/query_embed.ml#L138>) |
| Search.search_chunk_count | [lib/nema/search.ml:106](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L106>) |
| Search.eligible_chunk_ids | [lib/nema/search.ml:223](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L223>) |
| Search.bm25 | [lib/nema/search.ml:239](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L239>) |
| Search.vector_search_filtered | [lib/nema/search.ml:296](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L296>) |
| Search.vector_search | [lib/nema/search.ml:358](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L358>) |
| Search.hydrate_hits | [lib/nema/search.ml:414](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L414>) |
| Search.finalize | [lib/nema/search.ml:504](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L504>) |
| Search.search_now | [lib/nema/search.ml:558](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L558>) |
| Search.search | [lib/nema/search.ml:687](</home/ribelo/projects/ribelo/nema/lib/nema/search.ml#L687>) |
| Service.with_write_value | [lib/nema/service.ml:103](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L103>) |
| Service.create | [lib/nema/service.ml:129](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L129>) |
| Service.show_note | [lib/nema/service.ml:272](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L272>) |
| Service.note_identity | [lib/nema/service.ml:280](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L280>) |
| Service.health | [lib/nema/service.ml:297](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L297>) |
| Service.save_retry_error | [lib/nema/service.ml:378](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L378>) |
| Service.clear_retry_error | [lib/nema/service.ml:394](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L394>) |
| Service.accept_job | [lib/nema/service.ml:397](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L397>) |
| Service.accept_sync | [lib/nema/service.ml:420](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L420>) |
| Service.accept_rebuild | [lib/nema/service.ml:421](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L421>) |
| Service.require_damage_rebuild | [lib/nema/service.ml:423](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L423>) |
| Service.job_status | [lib/nema/service.ml:464](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L464>) |
| Service.plan_structural_changes | [lib/nema/service.ml:519](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L519>) |
| Service.publish_structural_plan | [lib/nema/service.ml:637](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L637>) |
| Service.structural_reconcile | [lib/nema/service.ml:728](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L728>) |
| Service.drain_watcher | [lib/nema/service.ml:767](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L767>) |
| Service.plan_paths | [lib/nema/service.ml:774](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L774>) |
| Service.merge_running_sync_reconcile | [lib/nema/service.ml:854](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L854>) |
| Service.flush_watch_manifest | [lib/nema/service.ml:889](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L889>) |
| Service.flush_pending_paths_if_quiet | [lib/nema/service.ml:977](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L977>) |
| Service.maybe_coalesce_watch | [lib/nema/service.ml:985](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L985>) |
| Service.close | [lib/nema/service.ml:1025](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1025>) |
| Service.flush_startup_watch_manifest | [lib/nema/service.ml:1037](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1037>) |
| Service.bootstrap_tag_catalog | [lib/nema/service.ml:1055](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1055>) |
| Service.reconcile_startup | [lib/nema/service.ml:1078](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1078>) |
| Service.startup_reconcile | [lib/nema/service.ml:1136](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1136>) |
| Service.fail_running_sync | [lib/nema/service.ml:1150](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1150>) |
| Service.fail_active_sync_embedding | [lib/nema/service.ml:1193](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1193>) |
| Service.mark_embedding_idle_or_waiting | [lib/nema/service.ml:1216](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1216>) |
| Service.materialize_cached_embeddings | [lib/nema/service.ml:1281](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1281>) |
| Service.process_embeddings_with_provider | [lib/nema/service.ml:1297](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1297>) |
| Service.process_embeddings_step_raw | [lib/nema/service.ml:1395](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1395>) |
| Service.process_embeddings_step | [lib/nema/service.ml:1456](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1456>) |
| Service.process_embeddings_once | [lib/nema/service.ml:1474](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1474>) |
| Service.complete_sync_if_embedding_ready | [lib/nema/service.ml:1485](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1485>) |
| Service.active_running_sync | [lib/nema/service.ml:1540](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1540>) |
| Service.continue_running_sync | [lib/nema/service.ml:1551](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1551>) |
| Service.run_sync_job | [lib/nema/service.ml:1602](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1602>) |
| Service.rebuild_schema_in_place | [lib/nema/service.ml:1727](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1727>) |
| Service.persist_rebuild_mutation_started | [lib/nema/service.ml:1743](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1743>) |
| Service.run_rebuild_job | [lib/nema/service.ml:1747](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1747>) |
| Service.plan_and_publish (local) | [lib/nema/service.ml:1758](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1758>) |
| Service.select_job | [lib/nema/service.ml:1920](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1920>) |
| Service.run_maintenance_once | [lib/nema/service.ml:1926](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1926>) |
| Service.job_selection_deadline | [lib/nema/service.ml:1970](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1970>) |
| Service.job_deadline | [lib/nema/service.ml:2005](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2005>) |
| Service.observe_work | [lib/nema/service.ml:2027](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2027>) |
| Service.run_due_background_work | [lib/nema/service.ml:2029](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2029>) |
| Service.wait_for_background_wake | [lib/nema/service.ml:2101](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2101>) |
| Service.wait_signal (local) | [lib/nema/service.ml:2103](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2103>) |
| Service.wait_watcher (local) | [lib/nema/service.ml:2107](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2107>) |
| Service.wait_deadline (local) | [lib/nema/service.ml:2114](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2114>) |
| Service.run_background | [lib/nema/service.ml:2130](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2130>) |
| Service.loop (local) | [lib/nema/service.ml:2131](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2131>) |
| Service.with_query_read_response | [lib/nema/service.ml:2184](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2184>) |
| Service.with_collection_page | [lib/nema/service.ml:2193](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2193>) |
| Service.embedding_coverage_snapshot_or_error | [lib/nema/service.ml:2211](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2211>) |
| Service.search_handler_validated | [lib/nema/service.ml:2234](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2234>) |
| Service.search_handler | [lib/nema/service.ml:2302](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2302>) |
| Service.run_cypher | [lib/nema/service.ml:2332](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2332>) |
| Service.handle_request | [lib/nema/service.ml:2451](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2451>) |
| Service.resume_pending_jobs | [lib/nema/service.ml:2596](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2596>) |
| Service.handler | [lib/nema/service.ml:2633](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2633>) |
| Service.resume_pending_rebuild | [lib/nema/service.ml:2647](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L2647>) |
| Vault.job | [lib/nema/vault.ml:190](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L190>) |
| Vault.walk_with_directories | [lib/nema/vault.ml:199](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L199>) |
| Vault.walk | [lib/nema/vault.ml:204](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L204>) |
| Vault.check_directory | [lib/nema/vault.ml:216](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L216>) |
| Vault.directory_candidate | [lib/nema/vault.ml:222](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L222>) |
| Vault.inspect | [lib/nema/vault.ml:283](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L283>) |
| Vault.file_job | [lib/nema/vault.ml:317](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L317>) |
| Vault.read | [lib/nema/vault.ml:329](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L329>) |
| Vault.load_file | [lib/nema/vault.ml:330](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L330>) |
| Vault.read_file | [lib/nema/vault.ml:334](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L334>) |
| Vault.close | [lib/nema/vault.ml:336](</home/ribelo/projects/ribelo/nema/lib/nema/vault.ml#L336>) |
| Watch_intake.create_with | [lib/nema/watch_intake.ml:28](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L28>) |
| Watch_intake.create | [lib/nema/watch_intake.ml:46](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L46>) |
| Watch_intake.drain | [lib/nema/watch_intake.ml:158](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L158>) |
| Watch_intake.validate_recovery | [lib/nema/watch_intake.ml:198](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L198>) |
| Watch_intake.acknowledge_recovery | [lib/nema/watch_intake.ml:212](</home/ribelo/projects/ribelo/nema/lib/nema/watch_intake.ml#L212>) |
| Watcher.refresh | [lib/nema/watcher.ml:123](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L123>) |
| Watcher.start_with | [lib/nema/watcher.ml:175](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L175>) |
| Watcher.start | [lib/nema/watcher.ml:204](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L204>) |
| Watcher.root_identity_verified | [lib/nema/watcher.ml:206](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L206>) |
| Watcher.note_directory | [lib/nema/watcher.ml:219](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L219>) |
| Watcher.poll | [lib/nema/watcher.ml:239](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L239>) |
| Watcher.changed_tree (local) | [lib/nema/watcher.ml:244](</home/ribelo/projects/ribelo/nema/lib/nema/watcher.ml#L244>) |
| Main.client_commands.client_post (local partial binding) | [bin/nema/main.ml:745](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L745>) |
| Main.client_commands.client_get (local partial binding) | [bin/nema/main.ml:746](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L746>) |
| Main.body.handle (local partial binding) | [bin/nema/main.ml:1057](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1057>) |

## Reproduction and evidence files

- [manifest.json](</tmp/suspend-token-cost/nema/manifest.json>): exact file/line denominator.
- [ast.jsonl](</tmp/suspend-token-cost/nema/ast.jsonl>): complete parsed event census (34,667 events).
- [analyze.mjs](</tmp/suspend-token-cost/nema/analyze.mjs>): resolver, roots, factory adjustment, and partial-binding amendments.
- [audit.mjs](</tmp/suspend-token-cost/nema/audit.mjs>): critical-region and generic-helper classification.
- [counts.json](</tmp/suspend-token-cost/nema/counts.json>) and [raw-counts.json](</tmp/suspend-token-cost/nema/raw-counts.json>): adjusted/raw point estimates; signaturesWithPartialBindings is the report numerator.
- [critical-sections.json](</tmp/suspend-token-cost/nema/critical-sections.json>), [audit-counts.json](</tmp/suspend-token-cost/nema/audit-counts.json>), and [generic-helpers.json](</tmp/suspend-token-cost/nema/generic-helpers.json>): site-level critical and helper inventories.
- [prototype-stats.json](</tmp/suspend-token-cost/nema/prototype-stats.json>): exact original/new line-change metrics.

All report/prototype/analysis writes are under /tmp/suspend-token-cost/nema. Nema and Ox sources were read-only. Dirty-tree warnings in Nix output describe pre-existing checkout state; no source changes were made.
