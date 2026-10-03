---
status: completed
package: docs (spike); measures ox, Leash, nema
consumer: Ox (ADR-0010); decides row 71
---

# Spike: what the suspension token costs

## Problem Statement

`suspend-token` (row 71) makes suspending inside a critical section a compile error by requiring `~io : Ox.Io.t` (a `yielding` value) on every operation that may suspend. The guarantee is verified (ADR-0010); the cost is not. Caps, the closest precedent, cost Leash about 150 `~caps` threading sites and grip 229 in 5.9 kloc (`docs/caps.md`, ^ncaps-21nk). Row 71 is built in ox either way; whether consumers migrate is decided on this spike's numbers.

## Solution

Measure, on ox and on the two consumers already on ox with the most concurrency (Leash, nema), how many signatures and call sites would carry `io`, and prototype the migration of one real module per consumer to see the code it produces.

## User Stories

1. As a maintainer, I want every operation in ox that may suspend listed (Ox and the Eio calls ox makes: channel, stream, promise, mutex, condition, sleep, timeout, I/O on flows and sockets, blocking pool), so that the token's reach is known. ^ntokcost-3m7a
2. As a maintainer, I want, for ox, Leash and nema separately: the number of functions that would need `~io` in their signature (transitively: a function that calls one that suspends), the number of call sites passing it, and both per kloc, beside the caps numbers, so that the cost is comparable to a cost already paid. ^ntokcost-k2xd
3. As a maintainer, I want the critical sections the token would protect counted (actor handlers, agent closures, mutex sections, `Cancel.protect`, status functions) and any current suspension inside one listed with file:line, so that the benefit is measured too. ^ntokcost-9pfv
4. As a maintainer, I want one module per consumer migrated in a scratch copy with the ADR-0010 token and explicit `bind ... [@nontail]` (the `ppx-let` expansion), compiled with the pinned compiler, and its diff summarised, so that the code it produces is seen, not imagined. ^ntokcost-w4hn
5. As a maintainer, I want a recommendation — migrate consumers, keep the token inside ox only, or drop it — with the numbers that decide it, so that row 71's consumer stories have a basis. ^ntokcost-c8ue

## Findings

Measured 2026-10-04 by Sol workers (one per codebase) on the pinned 5.4.0+ox with Eio 1.6. Evidence — census tools, per-codebase reports, site lists, prototypes, compile scripts — is in `evidence/`. Leash was read from a frozen snapshot of its working tree at HEAD `33635b52` with uncommitted edits (`evidence/leash/freeze.json`); the cited Leash files are copied to `evidence/leash/frozen/` so line numbers stay true.

The benefit is concrete: Leash has four bookkeeping sections waiting on an Actor request and a status function that can wait on a mutex or warning log; nema's documented non-suspending publication notifier reaches the journal logger. These are distinct from legitimate suspension while holding a general Eio mutex. The recommendations below keep that distinction.

### 1. Suspension inventory (^ntokcost-3m7a)

A suspension is a scheduler handoff, including one possible only under contention, an empty/full queue, or an error path. Blocking a system thread/domain in Unix, SQLite, OpenSSL, or Ladybug is not an Eio suspension. Pure constructors, promises' resolution, nonblocking stream takes, notifications, clock reads, and cancellation checks are not roots.

The production Ox implementation has **169 potentially suspending direct Eio/Eio_unix applications, using 48 operation spellings**. This table lists every discovered spelling; parentheses count application AST nodes, not lines. Six reviewed guarded Stream.add applications are excluded only under their existing single-domain/producer invariants, never by declaring general Stream.add non-suspending.

| Family | Operations used in Ox |
|---|---|
| Fibers | Eio.Fiber.List.map (1); Eio.Fiber.all (1), any (4), await_cancel (2), both (2), first (6), fork (4), fork_daemon (13), fork_promise (1), yield (2) |
| Promises | Eio.Promise.await (28), await_exn (3) |
| Locks and conditions | Eio.Mutex.use_ro (6), use_rw (3); Eio.Condition.await (1), await_no_mutex (1), loop_no_mutex (1); Eio.Semaphore.acquire (7) |
| Streams | Eio.Stream.add (5), take (3) |
| Switches | Eio.Switch.run (7), run_protected (1), on_release (8) |
| Time | Eio.Time.sleep (5), sleep_until (1), with_timeout (5), with_timeout_exn (2) |
| Flows | Eio.Flow.Pi.simple_copy (1); Eio.Flow.close (6), copy_string (12), shutdown (1), single_read (6), write (2) |
| Sockets | Eio.Net.accept (2), connect (1), getaddrinfo_stream (1), listen (1), with_tcp_connect (1) |
| Files | Eio.File.stat (1); Eio.Path.load (1), stat (1), with_open_in (1) |
| Processes/workers | Eio.Process.await (3); Eio.Pool.use (1); Eio_unix.Process.spawn_unix (1); Eio_unix.pipe (1), run_in_systhread (1) |
| Buffered reads | Eio.Buf_read.parse (1), conservatively effectful for a generic flow-backed reader |

There is also a standalone Eio.Resource.close reference in [Resource](<lib/ox/resource.ml#L11>). Function/field references are counted separately from applications in story 2.

**Fork is itself a yield point**, even if the child has not awaited anything: the installed [Fiber implementation](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/core/fiber.ml#L8-L9>) performs Fork and the [POSIX scheduler](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio_posix/sched.ml#L370-L373>) queues the parent and runs the child. Parent-side Scope.fork/fork_error and any consumer fork facade therefore consume current io; the child receives fresh io at invocation rather than capturing the parent's token.

Release registration is not automatically pure: on a finished switch, [on_release_full](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/core/switch.ml#L164-L177>) runs the release under cancellation protection synchronously before raising. The census includes registration and resource wrappers conservatively. A future API proving the switch active could narrow this.

Ox's propagated surface is:

| Surface | Operations requiring io or an io-aware invocation boundary |
|---|---|
| [Channel](<lib/ox/channel.ml#L38-L55>), [Select](<lib/ox/select.ml#L50-L106>) | Channel.send/receive; Select.select/receive and clause wait/sleep callbacks. Clause construction remains pure. |
| [Actor](<lib/ox/actor.ml#L50-L171>), [Agent](<lib/ox/agent.ml#L26-L101>) | Actor.create/tell/ask, Changes.next; Agent.create/request/get/update/get_and_update/cast/update_result/get_and_update_result. Actor.handle and Agent state callbacks remain non-suspending. |
| [Scope](<lib/ox/scope.ml#L45-L171>), [Concurrent](<lib/ox/concurrent.ml#L15-L81>) | Scope.run/supervised_error/fork/fork_error/fork_daemon/fork_error_daemon/await; Concurrent.par/both/all/for_each/race/race_first/with_background. |
| [Timeout](<lib/ox/timeout.ml>), [Retry](<lib/ox/retry.ml>), [Rate_limiter](<lib/ox/rate_limiter.ml#L89-L105>) | timeout, retry/repeat, rate acquire/run/run_or_drop. Deferred clock/sleep fields receive io when called, not at limiter creation. |
| [Resource](<lib/ox/resource.ml>), [Supervisor](<lib/ox/supervisor.ml#L203-L702>) | Resource.use_in_scope/use_closeable_in_scope; Supervisor.supervise/start/start_simple/start_child/stop/await/terminate_child and their launch/recovery/settlement helpers. Snapshot children is pure. |
| [Blocking](<lib/blocking/ox_blocking.ml#L65-L217>) | Pool.shutdown, run/try_run/run_result/try_run_result and both timeout variants, including admission/completion/drain. try_run only avoids waiting for admission, not waiting for a started worker. |
| [HTTP client](<lib/http/client.ml#L189>), [server](<lib/http/server.ml#L408-L608>), [TLS](<lib/http/tls_flow.ml#L47-L241>), [WebSocket](<lib/http/ws_client.ml#L161-L453>) | Client.request and buffered response reads; Server response writes/serve/run; TLS creation/handshake/read/write/flush/close/shutdown; WebSocket connect/send_text/send_binary/close/receive. |
| [IPC listener](<lib/ipc/listener.ml#L175-L347>), [Process.Child](<lib/process/child.ml#L19-L121>), [Process.Supervised](<lib/process/supervised.ml#L28-L103>) | Listener.run and peer/read/respond/drain paths; Child.spawn/await/output/stop; Supervised.start/stop and worker loop. |
| [RPC](<lib/rpc/correlator.ml#L76-L166>), [SQL pool](<lib/sql/pool.ml#L19-L162>), [migration](<lib/sql/migrate.ml#L403-L555>) | Correlator.create/call/close; pooled queries/execution/folds/connection/transaction/shutdown; migration run/run_to/undo/list_applied and execution helpers. Synchronous SQLite/C work itself is not an io root. |
| [OTEL](<lib/otel/ox_otel.ml#L142-L464>), [Logger](<lib/observability/logger.ml#L213-L285>) | OTEL.create/flush/shutdown/export/send/drain; current Logger.emit/log/debug/info/warn/error/span. Reporter creation is pure; emitter invocation is not. |
| [App](<lib/app/ox_app.ml#L15-L423>), [configuration](<lib/app/config.ml#L164-L182>) | Door/runtime run/test/execute/service boundaries, diagnostics and wakeup logging, configuration reads. Root callback signatures receive the token; status_query remains non-suspending. |
| [AI transport](<lib/ai/transport.ml#L115-L190>) and adapters | Transport.post_json/attempt/retry wait; chat.complete, OpenRouter Common.post/audio.create/embeddings.create/responses.post/create/create_text, realtime connect/send/receive/close, SystemOne.evaluate. Request constructors named create here really perform HTTP. |

The complete named-owner inventory below includes private/local functions as well as public APIs. Anonymous immediate callbacks belong to their closest named owner; deferred callback fields get an io parameter on invocation. This is not a promise that every value spelled create or close suspends.

<details>
<summary>Complete current-Logger Ox named-owner inventory (261 functions)</summary>

Locals with the same name at different lines are separate bindings. This records the propagated estimate, not 261 independently suspending primitives.

| Source | Functions | Binding:line |
|---|---:|---|
| [transport.ml](<lib/ai/transport.ml#L115>) | 4 | `attempt:115, wait:130, run:145, post_json:180` |
| [chat.ml](<lib/ai_chat/chat.ml#L26>) | 1 | `complete:26` |
| [ox_ai_chat.ml](<lib/ai_chat/ox_ai_chat.ml#L11>) | 1 | `complete:11` |
| [audio.ml](<lib/ai_openrouter/audio.ml#L63>) | 1 | `create:63` |
| [common.ml](<lib/ai_openrouter/common.ml#L10>) | 1 | `post:10` |
| [embeddings.ml](<lib/ai_openrouter/embeddings.ml#L60>) | 1 | `create:60` |
| [responses.ml](<lib/ai_openrouter/responses.ml#L229>) | 3 | `post:229, create:241, create_text:251` |
| [session.ml](<lib/ai_realtime/session.ml#L5>) | 4 | `connect:5, send:11, receive:27, close:34` |
| [ai_systemone/client.ml](<lib/ai_systemone/client.ml#L23>) | 1 | `evaluate:23` |
| [config.ml](<lib/app/config.ml#L164>) | 1 | `read_regular:164` |
| [ox_app.ml](<lib/app/ox_app.ml#L15>) | 15 | `serve:15, run_for_test_with_args:66, run_owned:94, run_owned_code:106, execute:151, run_for_test:274, log_posix_wakeup:305, posix_wakeup:314, tick:320, run_with_args:326, program:351, on_switch:372, read:390, run:409, run_simple:421` |
| [ox_blocking.ml](<lib/blocking/ox_blocking.ml#L65>) | 10 | `shutdown:65, reserve:86, try_reserve:108, execute:120, run:177, try_run:182, run_result:192, try_run_result:197, run_result_timeout:202, try_run_result_timeout:210` |
| [http/client.ml](<lib/http/client.ml#L43>) | 15 | `refill:43, perform:44, available:66, take_byte:68, read_line:74, loop:76, read_exact:90, loop:92, read_response:103, headers:105, chunks:140, trailers:153, until_close:170, request:189, perform:192` |
| [server.ml](<lib/http/server.ml#L220>) | 20 | `refill:220, next_byte:225, line:231, loop:233, take:247, loop:249, parse_head:262, headers:275, request_body:326, trailers:357, write_response:408, write_bytes:446, loop:460, serve_flow:478, loop:487, run_h1_on_socket:556, close_idle:569, run:574, accept:575, run_h1:608` |
| [service.ml](<lib/http/service.ml#L246>) | 1 | `h1:246` |
| [tls_flow.ml](<lib/http/tls_flow.ml#L47>) | 17 | `with_lock:47, drain:50, loop:51, flush:70, try_flush:75, feed:105, handshake:120, loop:121, single_read:139, loop:142, write_once:171, single_write:189, attempt:195, close:211, copy:228, shutdown:229, create:232` |
| [ws_client.ml](<lib/http/ws_client.ml#L50>) | 17 | `read_exact:50, loop:52, read_head:66, loop:68, create_tls:149, connect:161, perform:165, dial:192, finish:287, writing:295, send_frame:303, send_text:309, send_binary:312, close:314, read_frame:346, receive:403, loop:407` |
| [listener.ml](<lib/ipc/listener.ml#L175>) | 10 | `read_line:175, read:177, scan:179, respond:195, peer:211, refuse:215, work:233, monitor:248, drain:250, run:273` |
| [logger.ml](<lib/observability/logger.ml#L213>) | 10 | `emit:213, emit_if_enabled:228, log:260, debug:263, info:264, warn:265, error:266, span:268, run:276, finish:278` |
| [ox_otel.ml](<lib/otel/ox_otel.ml#L142>) | 13 | `post:142, send:152, send_metrics:199, export_metrics:211, send_window:212, drain:232, finish:285, worker:298, flush_window:305, loop:309, create:351, flush:437, shutdown:448` |
| [actor.ml](<lib/ox/actor.ml#L50>) | 7 | `next:50, enqueue:82, tell:85, ask:92, wait:98, create:133, loop:148` |
| [agent.ml](<lib/ox/agent.ml#L26>) | 9 | `create:26, loop:31, request:55, get:70, update:75, get_and_update:80, cast:85, update_result:92, get_and_update_result:98` |
| [channel.ml](<lib/ox/channel.ml#L38>) | 3 | `wait_changed:38, send:40, receive:48` |
| [concurrent.ml](<lib/ox/concurrent.ml#L15>) | 7 | `par:15, both:24, all:29, for_each:37, race:45, race_first:71, with_background:76` |
| [rate_limiter.ml](<lib/ox/rate_limiter.ml#L89>) | 4 | `acquire:89, run:93, wait_for_permit:94, run_or_drop:104` |
| [resource.ml](<lib/ox/resource.ml#L1>) | 2 | `use_in_scope:1, use_closeable_in_scope:11` |
| [retry.ml](<lib/ox/retry.ml#L2>) | 5 | `sleep:2, retry_loop:13, retry:29, repeat_loop:32, repeat:42` |
| [scope.ml](<lib/ox/scope.ml#L45>) | 7 | `run:45, supervised_error:144, fork_error:152, fork:160, fork_daemon:162, fork_error_daemon:167, await:171` |
| [select.ml](<lib/ox/select.ml#L50>) | 4 | `select:50, block:80, block:98, receive:106` |
| [supervisor.ml](<lib/ox/supervisor.ml#L203>) | 22 | `supervise:203, launch:230, settle_spontaneous:291, settle_induced:317, stop_entry:325, sweep:354, wait_ready:384, start_downs:411, go:412, recover:454, shutdown_all:485, loop:489, react:503, handle:510, config:609, launch_supervisor:621, start:631, stop:645, await:649, terminate_child:666, start_simple:682, start_child:694` |
| [timeout.ml](<lib/ox/timeout.ml#L1>) | 1 | `timeout:1` |
| [child.ml](<lib/process/child.ml#L19>) | 4 | `await:19, stop:28, spawn:42, output:60` |
| [supervised.ml](<lib/process/supervised.ml#L28>) | 4 | `stop:28, start:42, run:56, loop:59` |
| [correlator.ml](<lib/rpc/correlator.ml#L76>) | 5 | `close:76, create:84, loop:117, call:135, run:136` |
| [migrate.ml](<lib/sql/migrate.ml#L403>) | 13 | `query:403, execute:405, script:408, create_table:410, read_states:417, list_applied:453, apply_migration:482, run_migrations:507, loop:512, run:523, run_to:527, undo:540, loop:548` |
| [pool.ml](<lib/sql/pool.ml#L19>) | 18 | `guard:19, shutdown_state:21, create:32, make:41, shutdown:76, apply_timeout:78, use:86, select:112, returning:113, execute_compiled:115, run_schema:118, fold_select:120, query:125, fold:128, execute:131, execute_script:134, with_connection:137, with_transaction:144` |

</details>

### 2. Migration count and caps comparison (^ntokcost-k2xd)

Each arrow is **current, potentially suspending Logger → hypothetical never-suspending Logger**. Count functions once, not once per implementation/interface declaration. Applications are distinct affected OCaml AST application nodes, **not an exact prediction of literal ~io insertions**; bare function-value references are separate.

| Tree | Production kloc | Named ~io bindings | Affected applications | Bare references | Bindings/kloc | Applications/kloc | Applications + references/kloc |
|---|---:|---:|---:|---:|---:|---:|---:|
| Ox | 24.660 | 261 → 249 | 548 → 523 | 36 → 32 | 10.58 → 10.10 | 22.22 → 21.21 | 23.68 → 22.51 |
| Leash | 24.803 | 329 → 310 | 887 → 825 | 99 → 97 | 13.26 → 12.50 | 35.76 → 33.26 | 39.75 → 37.17 |
| nema | 27.798 | 318 → 316 | 622 → 606 | 38 → 38 | 11.44 → 11.37 | 22.38 → 21.80 | 23.74 → 23.17 |

The common denominator is production **.ml + .mli physical lines**, including blanks/comments, excluding tests, build output and vendor code: Ox **17,389 + 7,271 = 24,660 lines / 192 files**; Leash **20,573 + 4,230 = 24,803 / 83**; nema **24,509 + 3,289 = 27,798 / 131**. Leash's gross 41,391-line inventory excludes 16,588 lines of generated Mozilla PSL data ([implementation](</home/ribelo/projects/ribelo/leash/packages/leash/public_suffix_data.ml>), [interface](</home/ribelo/projects/ribelo/leash/packages/leash/public_suffix_data.mli>)); keeping that vendor table would falsely dilute its application rate to 21.43/kloc. Consumers were inspected read-only. Concurrent Leash changes required a [frozen source copy](<evidence/leash/freeze.json>): 2026-10-03T23:24:53.864Z–23:24:55.664Z UTC, working tree at HEAD 33635b527d7ba30ff1ca9a6a5a4a918558309983, not a clean-HEAD claim.

For an implementation-only kloc convention, using the same numerators:

| Tree | Bindings/.ml kloc | Applications/.ml kloc |
|---|---:|---:|
| Ox | 15.01 → 14.32 | 31.51 → 30.08 |
| Leash | 15.99 → 15.07 | 43.11 → 40.10 |
| nema | 12.97 → 12.89 | 25.38 → 24.73 |

These rates matter when comparing to a precedent that may not count interfaces: Leash is 43.11 rather than 35.76 applications/kloc. The historical grip denominator is not specified, so neither convention gives an exact matched comparison.

**Method and limits.** The pinned parser collects named functions, named locals, aliases, calls and bare references. Ox reaches its fixed point in six rounds from 108 direct owners (107 without logging). Resolve same-file/module names and Ox package APIs; manually add effectful functional-record dispatch, then propagate through both calls and references. Anonymous immediate callbacks belong to the nearest named owner. Deferred stored callbacks receive io **at invocation**, never by capturing a factory-time token. The adjusted counts exclude **8 Ox, 13 Leash and 5 nema deferred factories** from the io-parameter set; fields/signatures/adapters still change. Eager create/start that forks or performs I/O is not a deferred pure factory.

These are **uniform-threading edit estimates**, not a typed whole-program migration or a minimum. A named local helper may capture the caller's io instead of gaining its own parameter. Record callback and public-interface edits are additional locations: Leash has 82 named locals, one identifier alias and approximately 100 matching val declarations (329 + 100 = 429 declaration locations), without claiming 429 distinct functions. A stored yielding callback needs an invocation-time token/mode contract even where its pure factory is excluded. The untyped graph can miss unresolved callbacks or over-propagate through a reference not actually called on a path. In [Drive.act:38](<evidence/leash/frozen/drive.ml#L38>), ((t.act page) choice) text has **three affected AST nodes but normally one new token argument**. Partial/curry applications are counted consistently across the three trees; do not interpret the table as that many compulsory textual ~io occurrences.

Generic bind/map/protect helpers require **yielding callback modes**, not automatically an io parameter, and are excluded from these io-signature totals. Leash inventories six generic helpers plus 28 operator aliases; nema inventories 70 Result-bind definitions/aliases to review. These are candidates, not 34/70 proven necessary edits; the compiler prototypes below show why at least the yielding continuation path must change.

**Caps precedent.** [The historical Leash caps note](<docs/caps.md#L119>) reports 17 capability parameters/fields, three aliases, approximately **150 textual ~caps threading sites**, and 88 test lines. The Problem Statement's historical grip observation is **229 sites / 5.9 kloc ≈ 38.81/kloc**; it was not freshly recounted. Leash's **887 (35.76/kloc)** affected io applications are about **5.9× its old 150-site caps total**, or **3.9× grip's total**, at about **92% of grip's density**. nema's **622 (22.38/kloc)** are **2.7× grip's total**, at **58% of its density**; Ox's **548 (22.22/kloc)** are **2.4×**, at **57%**. This is a rough burden comparison: textual caps occurrences versus affected AST nodes, different trees/snapshots, and an unspecified historical grip denominator. Do not treat it as a matched benchmark.

**Logger sensitivity.** A genuinely non-parking Logger removes **12 bindings / 25 applications / 4 references** in Ox, **19 / 62 / 2** in Leash, and **2 / 16 / 0** in nema: altogether **33 / 103 / 6**, not most of the migration. Leash has 14 direct Logger plus eight dynamic t.warn applications (22 entries; 27 including five lifecycle-wrapper calls); four logging entries are on must-not-suspend paths (one filtered Actor Info and three status warnings sharing one adapter). nema has eight direct logging applications; Telemetry.observe and Service.observe_work are the two logging-only named bindings removed. This variant is a design census, **not an implemented logger**. The existing Logger cannot become safe just by dropping its token: replace producer-side journal/mutex/flow waits with bounded nonblocking enqueue/try-add, one writer fiber, and explicit overflow/drop counters reported by that writer. Awaited drain/shutdown stays a separate io API; arbitrary synchronous Reporter callbacks must not remain an unchecked producer-side escape.

Evidence and reproducible collectors live in scratch: [Ox collector](<evidence/census_ox.ml>) and [resolver](<evidence/resolve.py>), [current Ox census](<evidence/ox-census-current.txt>) and [nonblocking variant](<evidence/ox-census-nonblocking.txt>); [Leash report](<evidence/leash/REPORT.md>), [signatures](<evidence/leash/io-signatures.tsv>), [application sites](<evidence/leash/io-call-sites.tsv>), [graph](<evidence/leash/graph.json>); [nema report](<evidence/nema/REPORT.md>). The figures and complete Ox owner list are retained here because scratch is not a permanent repository artifact.

### 3. Protected sections and current suspensions (^ntokcost-9pfv)

#### Concrete violations first

- **Leash, snapshot/status policy: two immediate application positions in one function.** [Learning.status:441](<evidence/leash/frozen/learning.ml#L437-L443>) acquires pending_mu using Eio.Mutex.use_ro; even its pure counter-reading callback can wait for acquisition. [Line 442](<evidence/leash/frozen/learning.ml#L442>) calls proposals, whose error branches invoke t.warn at [129](<evidence/leash/frozen/learning.ml#L129>), [151](<evidence/leash/frozen/learning.ml#L151>), and [164](<evidence/leash/frozen/learning.ml#L164>). The [warning adapter](<evidence/leash/frozen/bin/main.ml#L1479>) calls Logger.warn, eligible for the current journal reporter. Cache the status counters/diagnostics outside the snapshot query rather than accepting io there.
- **Leash Actor, generic-API conflict but no demonstrated suspension in this configuration.** [Fold:459](<evidence/leash/frozen/tabs.ml#L459-L465>) logs Info; fold is supplied as [Actor.handle:3011](<evidence/leash/frozen/tabs.ml#L3011>). The general io-taking Logger API would reject this unyielding handler. But production [journal_level:Warn](<evidence/leash/frozen/bin/main.ml#L1878>) filters this Info from the journal, and optional OTEL emission uses its guarded non-parking queue. Do not count it as a current runtime suspension. Nonblocking Logger resolves the generic type conflict without depending on the configured level.

- **nema, explicit must-not-suspend contract: one callback.** [Gate's on_waiting contract](</home/ribelo/projects/ribelo/nema/lib/nema/gate.mli#L15-L19>) says the notifier runs with the mutex held and must not suspend. [Service:738-740](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L738-L740>) calls work_observer.run. [Production wiring](</home/ribelo/projects/ribelo/nema/bin/nema/main.ml#L1019-L1026>) reaches [Telemetry.observe:85/90](</home/ribelo/projects/ribelo/nema/bin/nema/telemetry.ml#L82-L93>): Logger.span and Logger.info. The [Door logger](<lib/app/ox_app.ml#L164-L171>) includes the journal reporter even when OTEL is enabled; [journal emission](<lib/observability/logger.ml#L114-L123>) takes an Eio mutex and writes to stderr. This is a real possible suspension, not just an unfortunate function name. Move notification outside the lock, or record state inside and emit afterward. Never-suspending logging would remove this specific logger path; arbitrary future observers still need the unyielding contract.
- **Leash, declared synchronous bookkeeping intent: four callbacks.** [Tabs:721-725](<evidence/leash/frozen/tabs.ml#L721-L725>) calls its protected use_rw sections synchronous bookkeeping. The bodies at [1076-1077](<evidence/leash/frozen/tabs.ml#L1076-L1077>), [1095-1097](<evidence/leash/frozen/tabs.ml#L1095-L1097>), [1187-1188](<evidence/leash/frozen/tabs.ml#L1187-L1188>), and [1303-1305](<evidence/leash/frozen/tabs.ml#L1303-L1305>) call transition/call, reaching [Actor.ask:560](<evidence/leash/frozen/tabs.ml#L559-L566>). Those waits can park even though the Actor fold itself never suspends. These are **intent violations**, not violations of general Eio.Mutex.use_rw semantics. Either move the actor request outside the short section, or explicitly make it a may-suspend transaction with reviewed invariants. Cancel.protect does not turn it into an atomic section.

The eight direct nema log applications include the two Telemetry sites above; they are not counted twice as new source sites. Current Ox has no discovered suspension inside its audited must-not-suspend bodies. Leash has seven immediate conflicting application positions: six can potentially suspend at runtime (two status paths and four declared-bookkeeping paths), while the Actor Info is a generic-API-only conflict. The three underlying t.warn sites and their adapter describe those same status paths, not additional protected callbacks. Legitimate I/O below is not labeled a defect.

#### Policy split

| Must not suspend: callback @ local once unyielding where once is appropriate | May suspend: takes current io and has yielding callback modes |
|---|---|
| Actor.handle; Agent owner-state init/read/update callbacks; service/state status queries; Stdlib mutex and C-state callbacks; proposed Ox.Mutex short-section body | General Eio mutex transactions; SQL condition waits; awaited OTEL drain; transport writes; cancellation-protected cleanup |

[Eio's mutex interface](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/eio_mutex.mli#L24-L39>) expressly allows its callbacks to suspend. [Cancel.protect](</home/ribelo/.cache/opam/5.4.0+ox/lib/eio/core/cancel.ml#L122-L128>) masks cancellation, not suspension. Lock acquisition can require io even when the acquired body is unyielding. The short Ox.Mutex variant would be a distinct contract, not a blanket replacement for Eio mutexes.

#### Ox inventory

- **Actor:** one protected handle invocation at [154](<lib/ox/actor.ml#L154>); must not suspend. The protected on_stop at [171](<lib/ox/actor.ml#L171>) is cleanup and may suspend. Actor.init at [142](<lib/ox/actor.ml#L142>) is a state value, not an initializer callback.
- **Agent:** protected request.run and init at [37/43](<lib/ox/agent.ml#L37-L43>). Seven public user callback contracts: init plus [get/update/get_and_update/cast/update_result/get_and_update_result](<lib/ox/agent.ml#L70-L101>); all owner-state callbacks must not suspend. Do not add these seven contracts to the two invocation sites as nine disjoint sections.
- **Mutex bodies:** **76 application sections**, excluding helper definitions: 33 Eio (including two try-lock bodies) and 43 Stdlib. The explicit short/C-state subset is **54 must-not-suspend** bodies: 11 SSL bodies and 43 Stdlib bodies. The other 22 Eio bodies remain general may-suspend; pure pool/rate metadata subsets could later use the short variant.
  - [TLS](<lib/http/tls_flow.ml#L47-L218>): 11 ssl_mu wrapper applications at 53, 76, 108, 122, 129, 135, 146, 161, 174, 184, 218, all short OpenSSL/C-state work; six read_mu/write_mu wrapper applications at 70, 126, 155, 172, 204, 217 and two write_mu try-lock bodies at 77/163 may suspend. Raw read at [106](<lib/http/tls_flow.ml#L105-L112>) precedes the protected SSL body; raw write at [65](<lib/http/tls_flow.ml#L53-L65>) follows release of ssl_mu. Holding write_mu across that write is intentional.
  - [WebSocket](<lib/http/ws_client.ml#L295-L306>): two native mutex bodies at 297/322 and the writing wrapper application at 304; general may-suspend.
  - [SQL pool](<lib/sql/pool.ml#L19-L106>): eight bodies, six guard applications at 22/27/93/98/100/106 and native use_ro/use_rw at 23/49. Condition.await at [25](<lib/sql/pool.ml#L23-L27>) and connection work at [93](<lib/sql/pool.ml#L86-L100>) are legitimate suspension.
  - [Rate limiter:90](<lib/ox/rate_limiter.ml#L89-L99>), [Correlator:158-163](<lib/rpc/correlator.ml#L158-L163>), [journal Logger:120](<lib/observability/logger.ml#L118-L123>): one body each. Correlator.write and journal flow write legitimately suspend; limiter sleep is outside the acquisition callback.
  - [IPC synchronized](<lib/ipc/listener.ml#L51-L62>): two Stdlib-protected map operations at 56/62. [SQLite guards](<lib/sql/sqlite.ml#L140-L220>): 41 applications (16 database, 25 statement), covering handle checks/C calls and transaction state. None may consume io; these are not asynchronous database pool waits.
- **Cancel.protect:** **13 source applications**, three critical and ten may-suspend. Critical: Actor.handle [154](<lib/ox/actor.ml#L154>), Agent request/init [37/43](<lib/ox/agent.ml#L37-L43>). May-suspend: HTTP server [585](<lib/http/server.ml#L585>), TLS [107](<lib/http/tls_flow.ml#L107>), IPC [341](<lib/ipc/listener.ml#L341>), OTEL [233](<lib/otel/ox_otel.ml#L233>), Actor.on_stop [171](<lib/ox/actor.ml#L171>), Child [29/105](<lib/process/child.ml#L29-L121>), Supervised [29/96](<lib/process/supervised.ml#L29-L103>), Correlator [162](<lib/rpc/correlator.ml#L162>). Concrete awaited work includes flow close, mutex acquisition, process/promise/time waits, Correlator.write at 163, and OTEL send/export_metrics at [272/274](<lib/otel/ox_otel.ml#L268-L280>). Supervised's guarded event emit at 97 is currently non-parking under its queue invariant.
- **Status:** [status_query](<lib/app/ox_app.ml#L13>) has one callback boundary and [SERVICE.status](<lib/app/ox_app.mli#L38-L44>) one abstract method contract. Representative pure snapshot operations are Blocking.Pool.stats, Correlator.stats, Actor.state/Changes.dropped, OTEL.dropped, Supervised.dropped and Supervisor.children. These seven snapshot operations are not seven SERVICE implementations. HTTP status parsing and process-exit decoders are excluded.

The counts overlap intentionally: a protected mutex body appears in both the mutex and Cancel.protect lists. They must not be summed into a single number of runtime intervals.

**Leash:** **42 audited regions, 16 must-not-suspend and 26 may-suspend**, with overlapping membership retained: one Actor handler, two Agent callbacks, eight named state/status functions, five declared-synchronous tab-mutex callbacks, eleven Cancel.protect callbacks, seven other Eio mutex bodies, and eight manual tab-lock instantiations. There are two additional explicit mutex acquisitions at [Tabs:727](<evidence/leash/frozen/tabs.ml#L727>) and [2539](<evidence/leash/frozen/tabs.ml#L2539>). No production Stdlib mutex, short Ox.Mutex, or separate C-state guard was found. The Unix advisory file-lock callback in [Playbook:1572](<evidence/leash/frozen/playbook.ml#L1572>) is not a scheduler-atomic short-section contract.

There are **73 distinct lexical io applications** across the protected-region inventory. The helper's 461 transitive reachable positions are an intentionally conservative, non-flow-sensitive expansion; they are not 461 runtime critical-section defects. [Learning:47](<evidence/leash/frozen/learning.ml#L45-L48>) legitimately waits on a condition; [Chrome:547](<evidence/leash/frozen/chrome.ml#L544-L547>) awaits shutdown; [download cleanup:34](<evidence/leash/frozen/download_setup.ml#L32-L35>) calls target close. Tab-lock browser/CDP transport is explicitly allowed to suspend. [Handoff](<evidence/leash/frozen/tabs.ml#L2536-L2539>) unlocks for work then reacquires; a lexical region count must not claim the unlocked interval holds the lock. No suspension was found in either Agent callback.

**nema:** 54 audited source sites after excluding the CLI exit-code classifier: **25 must-not-suspend, 29 may-suspend**. This convention includes wrapper definitions, applications, acquisitions and nested protection, so it is not directly comparable with Ox's 76 application-body count. The must-not subset is seven native open-state guards, four Stdlib Ladybug gate sites, eleven Stdlib vault lock/template sites, one native transaction callback, one Watch_intake status snapshot, and the on_waiting callback above. Actor/Agent callback sites and short Ox.Mutex applications are zero. There are **33 distinct legitimate io application positions** in may-suspend regions, deduplicated across nesting. They include [Gate condition waits:42/63](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml#L34-L65>), [Ladybug owner close:1116](</home/ribelo/projects/ribelo/nema/lib/ladybug/nema_ladybug.ml#L1104-L1121>), and publication lease bodies in [Service:737](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L737-L759>), [1246/1282](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1246-L1287>), [1368](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1368-L1377>), [1488](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1488-L1529>), and [1799](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L1799-L1810>). Gate's writer work is a general may-suspend transaction; only its waiting notifier has the stricter contract.

### 4. Compiled consumer prototypes (^ntokcost-w4hn)

Both are **actual consumer modules copied into scratch**, not extracted toy functions. Both use the pinned compiler **5.4.0+ox**, a real yielding unboxed token, precise callback modes, and explicit bind continuations rather than plain let*:

~~~ocaml
type io = { suspend : unit -> unit } [@@unboxed]
let bind r (f : ('a -> ('b, 'e) result) @ local once yielding) =
  match r with Ok value -> f value | Error error -> Error error
(* in a caller carrying io: *)
bind result (fun value -> suspend_or_continue ~io value) [@nontail]
~~~

The generic bind does not itself need io. The non-tail application prevents a local continuation from escaping into the caller's tail-call region. Plain let* currently rejects capture of a yielding io value ("used in a letop"); these prototypes test the explicit expansion, not an implemented ppx-let.

**Leash — [Download_setup](<evidence/leash/frozen/download_setup.ml>).** The full 72-line browser bootstrap module is copied. call, prepare and recursive loaded take io; five letop continuations become explicit binds with [@nontail]. Polling and target-close cleanup remain yielding; target bookkeeping/on_target is unyielding. Representative transformation:

~~~ocaml
(* before *)
let* created = call cdp "Target.createTarget" params in
let* id = field "targetId" created in
target := Some id;
on_target id;
(* attach, then poll *)

(* after: enclosing protect/timeout region preserved *)
bind (call ~io cdp "Target.createTarget" params) (fun created ->
  bind (field "targetId" created) (fun id ->
    Shim.critical_section (fun () -> target := Some id; on_target id);
    (* attach/poll receive io here *)
    loaded ~io ()) [@nontail]) [@nontail]
~~~

[Scratch Download_setup](<evidence/leash/download_setup.ml>) compiles **exit 0** with ocamlfind ocamlopt -package eio,yojson on **5.4.0+ox**. A negative copy injects Shim.sleep ~io in the real bookkeeping body and fails **exit 2** with the expected yielding-to-unyielding error. Ordinary Result.bind letop capture separately fails **exit 2** ("used in a letop"). Run:

~~~sh
nix develop -c sh evidence/leash/compile.sh
~~~

The [diff](<evidence/leash/prototype.diff>) replaces **29/72 original lines (40.3%)**, adding 29 and deleting 29, net zero. The helper's 58/72 = 80.6% is added-plus-deleted diff churn, **not** 80.6% unique original lines touched. These include experimental Shim name replacements, so neither percentage is a token-only repository-wide estimate. The [shim](<evidence/leash/shim.ml>) leaves CDP unlinked, does not implement timeout/cancellation/exception cleanup, and uses real Eio sleep only in the sleep wrapper: this is a **compile-mode prototype**, not a successful production link or a browser lifecycle test.

**nema — [Gate implementation](</home/ribelo/projects/ribelo/nema/lib/nema/gate.ml>) and [interface](</home/ribelo/projects/ribelo/nema/lib/nema/gate.mli>).** Reader/writer preference, condition relocking, writer registration and cancellation cleanup remain. release_read/with_read/with_write take io; create stays pure. Reader/writer work is local once yielding, whereas on_waiting and the reader-count mutation remain local unyielding.

Representative new writer body:

~~~ocaml
let with_write ~(io : Io.t @ yielding)
    ?(on_waiting : (unit -> (unit, 'e) result) @ local unyielding =
      fun () -> Ok ()) t
    (f : (unit -> ('a, 'e) result) @ local once yielding) =
  Shim.mutex_lock ~io t.mutex;
  (* original writer registration/protected cleanup remains *)
  let r = if t.active_readers > 0 then on_waiting () else Ok () in
  Shim.bind r (fun () ->
      while t.active_readers > 0 do
        Shim.condition_await ~io t.cond t.mutex
      done;
      f ()) [@nontail]
~~~

[Scratch Gate](<evidence/nema/gate.ml>) compiles, and the linked Eio smoke test executes yielding reader/writer callbacks and the explicit bind: **exit 0**. The negative notifier calling Shim.yield ~io fails **exit 2**, specifically "The value io is yielding but is expected to be unyielding". Implementation: **19/65 original lines touched (29.2%)**, 22 replacement/insertion lines, net +3. Interface: **3/19 original lines touched (15.8%)**, six replacement/insertion lines, net +3. Combined: 22/84 original lines touched (26.2%), net +6. These synchronization-heavy modules are not a whole-repository percentage forecast.

Commands run from the Ox root:

~~~sh
nix develop -c sh -c 'cd evidence/nema && ocamlfind ocamlopt -package eio -c io.ml shim.ml gate.mli gate.ml'
nix develop -c sh -c 'cd evidence/nema && ocamlfind ocamlopt -package eio_main -linkpkg io.cmx shim.cmx gate.cmx positive.ml -o positive && ./positive && ocamlc -version'
nix develop -c sh -c 'cd evidence/nema && ocamlfind ocamlopt -package eio -c negative.ml'
~~~

The [nema shim](<evidence/nema/shim.ml>) uses a trusted %identity callback representation conversion solely at immediate synchronous legacy Eio.Cancel.protect/use_ro calls. Eio locks, waits, and cancellation remain real; the token's smoke-test hook is no-op. This is not evidence that upstream Eio already exposes safe yielding callback types. Supporting shim/token scaffolding is a separate one-time cost. Production must concentrate any such adaptation in the audited Once boundary mandated by [ADR-0010](<docs/adr/0010-modes-type-ownership-and-lifetime.md>), not scatter casts through consumers.

The [provider-escape control](<evidence/provider_escape.ml>) compiled **successfully** despite an unyielding critical callback containing a call to an unrestricted with_io provider and a token-mediated yield. Therefore private token construction is necessary but not sufficient: **the ability to mint/provide io must also be restricted**. Door is the privileged root; parent forks require current io before supplying a fresh child token; ordinary nested Scope.run consumes io rather than minting one. Captured-token rejection alone does not close a public-provider or raw-Eio escape hatch.

### 5. Recommendation (^ntokcost-c8ue)

**Build the checked Ox API and migrate both consumers in stages; do not stop permanently at an unchecked Ox-only facade.** First remove the current must-not-suspend violations and give Logger a genuinely non-parking producer API. The measured costs are substantial but not disproportionate to the caps precedent; the benefit is a compiler-enforced boundary at concrete state/publication contracts, not a ban on all mutex or cleanup waits.

| Layer | Decision | Numbers and reason |
|---|---|---|
| Ox | Implement the public io contract and own the mode boundary. | Current estimate 261 bindings / 548 affected applications; nonblocking Logger 249 / 523. Protect 54 short mutex/C-state bodies, three owner-state Cancel.protect bodies, Actor/Agent contracts and pure status queries. No current Ox must-not-suspend violation was found, so this is prevention rather than a claimed bug fix. |
| Leash | Migrate, beginning with Tabs state transitions and snapshot status. | Current 329 / 887; nonblocking Logger 310 / 825, 33.26 applications/kloc. Four declared bookkeeping bodies currently wait on Actor.ask; status can wait on a mutex or warning log. Nonblocking Logger removes the status-warning and generic Actor-Info conflicts, **not** the mutex-acquisition or four bookkeeping waits. |
| nema | Migrate, beginning with Gate and work_observer. | Current 318 / 622; nonblocking Logger 316 / 606, 21.80 applications/kloc. Gate's documented non-suspending notifier currently reaches a journal span/log. Keep its notification pure/non-parking while real mutex/condition waits remain io-taking. |

The scratch changes touched **29/72 original Leash lines (40.3%, net zero)** and **22/84 original Gate implementation/interface lines (26.2%, net +6)**. Small selected modules are not whole-tree churn predictors: they show real annotation/bind syntax, not effortless propagation. Nevertheless Leash's current application density (35.76/kloc) is near the old grip caps observation (38.81), and nema/Ox are around 22/kloc. On an implementation-only denominator, the current densities are Leash 43.11, nema 25.38 and Ox 31.51/kloc; Leash is slightly above the historical 38.81 observation, not cheaper under every convention. Nonblocking Logger saves only about **5% of all affected application nodes** (103/2,057), so it improves the critical contracts without pretending to erase migration cost.

Sequence: (1) make declared short callbacks actually short—move waits/I/O outside them or publish nonblocking owner-state snapshots; (2) introduce the Ox-owned unyielding boundaries and private token plumbing; (3) migrate consumer roots, callback fields, forks and required yielding binds; (4) close bypasses with the raw-concurrency gate and compile-negative coverage. Gate **all potentially suspending APIs**, including indirect wrappers and raw fork/release registration; restricting only Eio names while leaving a no-io legacy Ox wrapper is not sufficient. Trusted Eio mode adapters belong in Ox/Once, not copied into consumers.

**Ox-only is an intermediate compatibility stage, not the consumer guarantee.** Any retained legacy facade must be explicitly unchecked and forbidden inside checked critical code: unchanged no-io consumer wrappers can still suspend there just like raw Eio. Public unrestricted token providers also defeat the guarantee (the escape prototype compiles); Door is the privileged root, nested Scope.run consumes current io, and fork registration consumes parent io before giving its child a fresh token. Without those restrictions, drop the *claim* that critical sections cannot suspend—the token parameter alone does not establish it. With them, the measured consumer cost and actual violations support migration rather than dropping row 71.

No runtime overhead or complete production migration was measured. The compiler evidence establishes the chosen value/mode contract and explicit-bind path; trusted shims and limited runtime exercises do not establish typed safety for today's entire Eio API.
