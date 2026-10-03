# Ox's floor, item by item

ADR-0009 makes Scala Ox (https://ox.softwaremill.com, table of contents as of 2026-09-29) the floor of this library's core: everything on it exists in direct style, or is recorded here with a reason. This table is that check [^nfloor-37ic]: one row per item of Ox's table of contents, one status each.

- `have (module)` — exists in the tree today; the module named was checked in `lib/`.
- `spec (row)` — a delivery-map row specifies it; not yet built.
- `design (flow.md)` — designed in `docs/design/flow.md`; built in row 76.
- `rejected (reason)` — deliberately absent, with the reason.

The two error kinds are shared by Scala Ox and this OCaml library: unrecoverable errors are exceptions, untyped on purpose; recoverable errors are values (`result` with polymorphic variants) that combinators know through their result type (`docs/why-ox.md`). A row changes status when its spec lands. Every item on the floor is built (ADR-0009; ADR-0003 as amended on 2026-10-04: Ox is its own consumer). The items this table once rejected "for want of a consumer" are specs now (rows 76–82); what stays rejected is rejected for a technical reason that holds without any consumer.

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
| Streaming APIs, Flows: creating, transforming, running, concurrency | spec (row 76, flow.md) |
| Flows: files and I/O, InputStream/OutputStream, files | spec (row 76, flow.md) |
| Flows: JSON (NDJSON, arrays) | spec (row 76, flow.md) |
| Flows: text transformations, logging | spec (row 76, flow.md) |
| Flows: reactive streams interoperability | rejected (a JVM interface: there is no Publisher/Subscriber standard to bridge to in OCaml) |
| Channels: sinks, sources, handling closed channels | have (`Channel`) |
| Transforming channels (eager), capacity, discharging | spec (row 76, flow.md) |
| Selecting from channels: receive exactly one from many, mixed send/receive | have (`Select.receive`, `Select.select`) |
| Selecting: closed channels (done/error) | have (`Select`; a closure is a typed outcome) |
| Selecting: default clauses, select with timeout | have (`Select.default_clause`, `Select.timeout_clause`) |
| Error propagation, backpressure | spec (row 76, flow.md) |
| **Scheduling** | |
| Retries API: operation, configuration, examples | have (`Retry.retry`, `Retry.policy`, `Schedule`) |
| Retries: adaptive retries | spec (row 77) |
| Repeat API | have (`Retry.repeat`) |
| Scheduled: schedule, configuration | have (`Schedule`) |
| **Resiliency & utilities** | |
| OxApp: `run(args)` returning an exit code | have (`Ox_app.run_with_args`, `run`; `exit_code` maps a typed error) |
| OxApp: root scope, background forks in the app's scope | have (the root `Eio.Switch.t` the program receives; forks are waited for) |
| OxApp: SIGINT/SIGTERM as a clean stop | have (`Ox_app` signal monitor, `request_stop`; exit 0, Ox's default) |
| OxApp: `OxApp.Simple` | have (`Ox_app.run_simple`, `Config.none`) |
| OxApp: `WithEitherErrors`, `handleError` | have (`Ox_app.run ?exit_code`) |
| OxApp settings: `interruptedExitCode` | have (`interrupt_exit` for owned-code commands; the service exits 0 like Ox's default; a service-wide setting is a field of the Door spec record, row 68) |
| OxApp settings: `handleException`, `handleInterruptedException` | have (the Door renders the full `Cause` to stderr and exits 2; an interruption the Door requested is silent) |
| OxApp settings: `threadFactory` | rejected (fibers, not threads; fiber-local context crosses `fork` by itself) |
| OxApp settings: `shutdownTimeout` | rejected (Eio teardown is cooperative cancellation; a hard exit timer would cut flushes short; the supervisor's stop timeout — systemd `TimeoutStopSec` — owns it) |
| Rate limiter API: `runBlocking`, `runOrDrop` | have (`Rate_limiter.run`, `run_or_drop`) |
| Rate limiter: fixed window, sliding window, leaky bucket (start-time algorithms) | have (`Rate_limiter.Fixed_window`, `Sliding_window`, `Token_bucket`) |
| Rate limiter: custom algorithms | have (`Rate_limiter.algorithm`, `Custom`) |
| Rate limiter: duration algorithms (whole execution span) | spec (row 78) |
| Resources: `use`, `useCloseable` | have (`Fun.protect`; `Eio.Switch.run` with `Eio.Switch.on_release`) |
| Resources: `useInScope`, `useCloseableInScope`, `releaseAfterScope` | have (`Resource.use_in_scope`, `use_closeable_in_scope`; `Eio.Switch.on_release`) |
| Resources: `resourceScope` | have (`Eio.Switch.run`) |
| Control flow methods (`forever`, `never`, `repeatWhile`…) | have (stdlib recursion; `Eio.Fiber.await_cancel` for never) |
| CPU-intensive operations: `computeIntensive`, the compute pool | spec (row 80; `@ portable` work, capability-free) |
| Actors: ask, tell, close | have (`Actor`: `ask`, `tell`, `try_tell`, `state`, `changes`, stop with the switch; `Agent` for serialized closures; `Supervisor` for restartable child scopes) |
| Circuit Breaker | spec (row 79) |
| Utilities (`pipe`, `tap`, `timed`, `unsupervised`…) | have (the stdlib's `Fun` and pipe operator; `Eio.Time`) |
| **Integrations** | |
| Kafka flows | spec (row 82; needs a client-library ADR first) |
| Inheritable MDC using Logback | have (fiber-local `Ox_observability.Context`) |
| Cron scheduler | spec (row 81) |
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
