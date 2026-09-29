# Ox's floor, item by item

ADR-0009 makes Scala Ox (https://ox.softwaremill.com, table of contents as of 2026-09-29) the floor of this library's core: everything on it exists in direct style, or is recorded here with a reason. This table is that check [^nfloor-37ic]: one row per item of Ox's table of contents, one status each.

- `have (module)` — exists in the tree today; the module named was checked in `lib/`.
- `spec (row)` — a delivery-map row specifies it; not yet built.
- `design (flow.md)` — designed in `docs/design/flow.md`, built when a consumer pulls it.
- `rejected (reason)` — deliberately absent, with the reason.

The two error kinds are shared by Scala Ox and this OCaml library: unrecoverable errors are exceptions, untyped on purpose; recoverable errors are values (`result` with polymorphic variants) that combinators know through their result type (`docs/why-ox.md`). A row changes status when its spec lands; a row that says `rejected` is reopened by a consumer's story, not by this document. ADR-0009's list (`RateLimiter`, `select`, `Actor`, `OxApp`, `Flow`) does not name the circuit breaker, adaptive retries, cron or the CPU pool; they are recorded as rejected for want of a consumer (ADR-0003), which is the one place this table is stricter than "nothing on the floor is skipped".

| Ox item | Status |
| --- | --- |
| **Project info** (community, dependency, scope, AI assistants) | rejected (not a feature) |
| **Basics** | |
| Direct style | have (Eio; `docs/why-ox.md` §4) |
| Error handling: unrecoverable errors | have (exceptions; `Scope.run` classifies them as defects) |
| Error handling: recoverable errors | have (`result` with polymorphic variants; `Ox.Result.Syntax`) |
| Boundary/break for `Either` | have (`Result.Syntax` `let*`/`let+`) |
| Converting to exceptions, mapping errors | have (`Result.get_ok`, `Result.map_error` from the stdlib) |
| **High-level concurrency** | |
| Running computations in parallel (`par`), with application errors | have (`Concurrent.par`, `both`, `all`) |
| Race two computations, variants, application errors | have (`Concurrent.race`, `race_first`) |
| Parallelize collection operations: `mapPar`, `foreachPar` | have (`Concurrent.for_each ~concurrency`) |
| `filterPar`, `collectPar` | have (`Concurrent.for_each` then `List.filter_map`; no named operator) |
| Timeout a computation | have (`Timeout.timeout`, an alias of `Eio.Time.with_timeout`) |
| **Structured concurrency** | |
| What is structured concurrency | have (Eio) |
| Fork & join, types of forks, supervision, user and daemon forks | have (`Scope.fork`, `fork_error`, `await`, `fork_daemon`, `fork_error_daemon`) |
| Unsupervised scopes | have (`Eio.Switch.run` and `Eio.Fiber.fork` directly) |
| Cancelling forks, customizing thread creation | have (`Eio.Cancel`; fibers, no threads to customize) |
| Integrating structured concurrency with other libraries | have (`Ox_blocking` for blocking calls; `Eio` adapters) |
| Error handling in scopes: supervised scope, with application errors | have (`Scope.supervised_error`) |
| Fork locals | have (`Eio.Fiber.with_binding`; `Ox_observability.Context`) |
| Interruptions, uninterruptible operations | have (`Eio.Cancel`, `Eio.Cancel.protect`; `Interrupt_id` carries identity) |
| **Streaming** | |
| Streaming APIs, Flows: creating, transforming, running, concurrency | design (flow.md) |
| Flows: files and I/O, InputStream/OutputStream, files | design (flow.md) |
| Flows: JSON (NDJSON, arrays) | design (flow.md) |
| Flows: text transformations, logging | design (flow.md) |
| Flows: reactive streams interoperability | rejected (no consumer; no JVM) |
| Channels: sinks, sources, handling closed channels | have (`Channel`) |
| Transforming channels (eager), capacity, discharging | design (flow.md) |
| Selecting from channels: receive exactly one from many, mixed send/receive | have (`Select.receive`, `Select.select`) |
| Selecting: closed channels (done/error) | have (`Select`; a closure is a typed outcome) |
| Selecting: default clauses, select with timeout | have (`Select.default_clause`, `Select.timeout_clause`) |
| Error propagation, backpressure | design (flow.md) |
| **Scheduling** | |
| Retries API: operation, configuration, examples | have (`Retry.retry`, `Retry.policy`, `Schedule`) |
| Retries: adaptive retries | rejected (no consumer; a `Rate_limiter` around the attempt or an `is_worth_retrying` policy covers today's uses) |
| Repeat API | have (`Retry.repeat`) |
| Scheduled: schedule, configuration | have (`Schedule`) |
| **Resiliency & utilities** | |
| OxApp: `run(args)` returning an exit code | have (`Ox_app.run_with_args`, `run`; `exit_code` maps a typed error) |
| OxApp: root scope, background forks in the app's scope | have (the root `Eio.Switch.t` the program receives; forks are waited for) |
| OxApp: SIGINT/SIGTERM as a clean stop | have (`Ox_app` signal monitor, `request_stop`; exit 0, Ox's default) |
| OxApp: `OxApp.Simple` | have (`Ox_app.run_simple`, `Config.none`) |
| OxApp: `WithEitherErrors`, `handleError` | have (`Ox_app.run ?exit_code`) |
| OxApp settings: `interruptedExitCode` | have (`interrupt_exit` for owned-code commands; the service exits 0 like Ox's default; a service-wide setting is pulled by a consumer that wants one) |
| OxApp settings: `handleException`, `handleInterruptedException` | have (the Door renders the full `Cause` to stderr and exits 2; an interruption the Door requested is silent) |
| OxApp settings: `threadFactory` | rejected (fibers, not threads; fiber-local context crosses `fork` by itself) |
| OxApp settings: `shutdownTimeout` | rejected (Eio teardown is cooperative cancellation; a hard exit timer would cut flushes short; the supervisor's stop timeout — systemd `TimeoutStopSec` — owns it) |
| Rate limiter API: `runBlocking`, `runOrDrop` | have (`Rate_limiter.run`, `run_or_drop`) |
| Rate limiter: fixed window, sliding window, leaky bucket (start-time algorithms) | have (`Rate_limiter.Fixed_window`, `Sliding_window`, `Token_bucket`) |
| Rate limiter: custom algorithms | have (`Rate_limiter.algorithm`, `Custom`) |
| Rate limiter: duration algorithms (whole execution span) | rejected (no consumer; `algorithm` has no release hook — add one when a consumer needs it) |
| Resources: `use`, `useCloseable` | have (`Fun.protect`; `Eio.Switch.run` with `Eio.Switch.on_release`) |
| Resources: `useInScope`, `useCloseableInScope`, `releaseAfterScope` | have (`Resource.use_in_scope`, `use_closeable_in_scope`; `Eio.Switch.on_release`) |
| Resources: `resourceScope` | have (`Eio.Switch.run`) |
| Control flow methods (`forever`, `never`, `repeatWhile`…) | have (stdlib recursion; `Eio.Fiber.await_cancel` for never) |
| CPU-intensive operations: `computeIntensive`, the compute pool | rejected (single-domain caveat of ADR-0009; no consumer crosses domains; `Ox_blocking` covers blocking calls) |
| Actors: ask, tell, close | spec (row 47) |
| Circuit Breaker | rejected (not on ADR-0009's list; no consumer) |
| Utilities (`pipe`, `tap`, `timed`, `unsupervised`…) | have (the stdlib's `Fun` and pipe operator; `Eio.Time`) |
| **Integrations** | |
| Kafka flows | rejected (no consumer) |
| Inheritable MDC using Logback | have (fiber-local `Ox_observability.Context`) |
| Cron scheduler | rejected (no consumer; `Schedule` has no cron expression) |
| Propagating OpenTelemetry context | have (`Ox_observability.Context`, `Ox_otel`) |
| HTTP server using Tapir | have (`Ox_http` server and routing) |
| HTTP client using sttp | have (`Ox_http` client) |
| **Other topics** | |
| Stability of modules, blogs, videos, dictionary | rejected (not a feature) |
| Best practices: small scopes, callback APIs through channels, avoid returning `Fork` | have (`docs/why-ox.md`; `Channel` for callbacks) |
| Best practices: use flows instead of channels | design (flow.md) |
| Performance | rejected (not a feature) |
| Comparing Ox & Gears, Ox & functional effects | have (`docs/adr/0009-ox-is-the-floor.md`, `docs/why-ox.md`) |

## For consumers [^nfloor-8qx2]

A per-site or per-model request limit in a consumer (Leash's model calls and site requests first) is a `Rate_limiter` created once from the Door's clock and wrapped around the call, `Rate_limiter.run limiter (fun () -> call ())`, never a sleep between calls: the limiter is cancellable while it waits, consumes nothing when cancelled, and a mock clock tests it. Wait on several channels with `Select`, not by polling. Register a resource with `Resource.use_in_scope` or `Eio.Switch.on_release` on the switch that owns it. Consumer-facing instructions live where the consumer keeps them: the `leash` skill in the dotfiles library is an operator's guide to the Leash CLI, not a place for Ox API guidance, so this section and Leash's own `AGENTS.md` and `CONTEXT.md` are where the guidance belongs.

## OxApp against the Door

Each item of OxApp (https://ox.softwaremill.com/latest/utils/oxapp.html) has a case in `test/app/oxapp.ml` [^nfloor-6n2e]: the arguments and exit code, `OxApp.Simple` (`Ox_app.run_simple`, no config), a background fork of the app's scope, `handleError` and `handleException`, and SIGTERM as a clean stop with the scope's releases run. Where the Door differs from Ox it is on purpose: a defect exits 2, not 1, so it can be told from a typed failure; and Ox's process-wide `Runtime.addShutdownHook` is a signal monitor fiber that requests the interruption of the root switch.
