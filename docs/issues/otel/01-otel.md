---
status: ready-for-agent
package: ox_otel
consumer: Exergy, nema and configured Door telemetry
priority: P1
---

# OTLP exporter: inherited span context and bounded ending

## Problem Statement

The exporter already owns a caller-scoped worker and recovers records on switch release. Its span converter exports correlation IDs from context but omits inherited business attributes, violating the existing context story. Its ending has unbounded transitions: Stop admission precedes the timeout, cancellation can leave a sealed exporter with no Stop, consumed Flush resolvers are not retained during metric export, automatic release has no total budget, and explicit Stop does not retire the worker. Existing success-only collector tests do not prove these suspended lifecycle transitions.

## Solution

Merge inherited business context into completed spans using explicit local-field precedence. Make ending one bounded ownership transition with a shared terminal result, recoverable control resolvers and retired worker. Require an explicit finite total ending budget, distinct from individual send deadlines. Exercise the public exporter and configured Door rather than patching application workarounds.

## User Stories

1. As nema's service author, I want an OTLP reporter for Logger records and completed Logger spans with inherited context, so service logs and span outcomes go to their respective OTLP endpoints without a second tracing API. ^notel-6m2q
2. As nema's service author, I want a caller-scoped exporter over a borrowed eta_http client, endpoint and resource identity, so shutdown drains telemetry before nema releases its HTTP client. ^notel-j9vc
3. As an operator, I want bounded queues, signal-specific batches, drop counts, and explicit flush/shutdown settlement, so overload uses finite memory and admitted records are not silently abandoned on normal shutdown. ^notel-p4xe
4. As a kernel maintainer, I want v1's pure OTLP/JSON resource/scope/span/log wire encoding and regression assertions adapted to the new Logger record types, so numeric timestamps, severity and attributes remain valid OTLP without copying the effect runtime. ^notel-z7dk
5. As nema's service author, I want typed transport/status failures and a shutdown result that distinguishes a failed or timed-out drain, so telemetry failures are actionable without exposing response bodies or swallowing cancellation. ^notel-t8br
6. As a service author, I want pending telemetry exported when the switch that owns the exporter ends — including on a Door SIGTERM stop — without calling shutdown myself, so that the last records before a stop are not lost. ^notel-1stb
7. As a service author, I want inherited provider, endpoint, symbol and db attributes on completed exported spans, so that span search has the same business context as correlated logs. ^notel-nbvl
8. As a service author, I want explicit span fields to override duplicate inherited business keys, so that a local operation can refine context deterministically. ^notel-uydw
9. As a tracing author, I want trace_id, span_id and parent_span_id handled as tracing controls rather than ordinary business attributes, so that correlation and parentage remain correct. ^notel-p11y
10. As a service author, I want nested and forked spans to inherit context without leaking local fields to siblings or the caller, so that concurrent provider traces stay isolated. ^notel-jda9
11. As an operator, I want one explicit finite total ending budget shared by explicit shutdown and automatic owner release, so that an unresponsive collector cannot hold teardown indefinitely. ^notel-056b
12. As an operator, I want that budget to cover admission/sealing, recovered and in-flight batches, metric-window export and final settlement, so that timeout is not installed after blocking work has already occurred. ^notel-jx0z
13. As a service author, I want concurrent/repeated shutdown calls to join one terminal ending and return its recorded result, so that a deadline failure cannot later masquerade as a successful drain. ^notel-s12c
14. As a service author, I want cancelling a caller during a full-queue shutdown transition not to strand the sealed exporter, so that a surviving waiter or release hook can finish it. ^notel-48tm
15. As a service author, I want a consumed Flush command to stay owned until its resolver settles, including cancellation during metric export, so that external flush callers do not wait forever after the owner is cancelled. ^notel-hjd5
16. As a service author, I want every admitted Flush/Stop control to settle once during worker failure, owner release or deadline expiry, so that no detached command is forgotten. ^notel-d52a
17. As an operator, I want ending-budget expiry reported as Drain_deadline with observable bounded abandoned-work accounting, so that incomplete export is not reported as successful drain. ^notel-od2q
18. As a resource owner, I want a completed ending to retire the exporter worker and stop further HTTP sends, so that explicit shutdown ends the exporter before its borrowed client is released. ^notel-m8ax
19. As a service author, I want cancellation recovery to retain the existing at-least-once policy for uncertain in-flight sends, so that records are recovered without claiming exactly-once delivery. ^notel-opp7
20. As an operator, I want per-request deadlines and the total ending deadline tested independently, so that several individually bounded batches cannot multiply the shutdown budget. ^notel-g1e1
21. As a test author, I want configured Door shutdown and SIGTERM against a latching local collector to settle within the total budget, so that the guarantee holds at the application ownership boundary. ^notel-z5vn
22. As a security-conscious operator, I want secret headers and raw collector bodies absent from transport, invalid-header and error-callback diagnostics, so that broader failure coverage preserves the existing privacy contract. ^notel-nf92

23. As a flush caller, I want ending to wake or reject a full-queue admission wait started before sealing, so that worker retirement cannot leave me blocked forever. ^notel-5qi9

24. As a service author, I want exported logs and spans to contain one business attribute per key with explicit-field precedence over inherited context, so that correlation never produces ambiguous duplicate keys. ^notel-dzpj

## Implementation Decisions

- Logger remains independent of the exporter. Convert its completed end records into OTLP spans; suppress starts, retain resource/scope envelopes and existing metrics. Do not revive the old effect runtime or a process-global SDK.
- For both exported spans and correlated logs, merge inherited business attributes first and explicit record fields second, emitting exactly one value per key. Exclude trace-control keys from ordinary attributes and continue using them for native trace/span/parent IDs. Redact values before serialization; resource identity stays separate.
- An exporter receives an explicit finite ending budget at construction from its owner. A single absolute deadline starts when shutdown or owner release first begins ending; queue admission, all sends and recovery consume that same budget. Individual request deadlines cannot reset or extend it.
- Ending has one recorded terminal result. Expiry seals admission, settles outstanding controls with a typed deadline failure, accounts for unfinished work and retires the worker; it is not merely a caller wait timeout while background drain continues. Make the public shutdown API express this one-budget model and update callers rather than retaining a competing per-caller-timeout compatibility mode.
- Caller interruption remains Eio interruption, not Drain_deadline. It may cancel that waiter, never corrupt shared admission/ending state. Keep shutdown progress pool/exporter-owned or cancellation-safe until the shared ending or owner release can take over.
- Record ownership includes active Flush/Stop controls, pending/queued records and uncertain in-flight batches/windows. Every admitted control resolver has exactly one owner until completion. Sealing/ending also wakes or rejects Flush/Stop admission waiters that checked openness before becoming blocked: no pre-seal caller can enqueue into a queue whose worker is retired. Worker retirement and release recovery must not both resolve or send the same known-completed work.
- Preserve at-least-once recovery when a cancelled request may already have reached the collector; no transparent retries of a confirmed collector refusal and no exactly-once claim. Once terminal ending is recorded, no further send is allowed.
- Abandoned-work accounting is a bounded count/summary for unsent or uncertain work at expiry, not payload retention and not an exactly-known remote loss count. Do not silently reclassify it as ordinary queue rejection. Error callbacks must be nonparking summaries and cannot prevent internal controls/ending from settling.
- Borrow the explicit native HTTP client and respect its response-phase contract. Do not trace exporter transport recursively, log request secrets, or retain collector bodies for diagnostics.

## Testing Decisions

- Confirmed seams: public reporter/flush/shutdown calls and configured Door/SIGTERM against a local latching collector. Memory reporters alone cannot prove exported attributes or ending budgets.
- Assert inherited provider/endpoint/db on parent and child spans and their correlated logs; explicit fields override duplicate context keys with exactly one attribute per key in both signal encodings, control keys are not ordinary attributes, Redact remains protected, and sibling/fork context is isolated.
- Saturate the record queue while the collector holds a batch. Start shutdown, cancel the admitting caller and keep a second waiter; release or expiry must settle the shared ending without relying on owner teardown to enqueue a missing Stop.
- With a saturated queue, start Flush outside the exporter owner so it blocks before admission; begin ending and let its budget expire while the collector remains stalled. The surviving Flush caller must wake with the recorded failure, not hang or enqueue after worker retirement.
- Let the worker consume Flush, then stall its metric POST and cancel the exporter-owning switch from a different scope. The surviving flush caller must settle once through recovery/expiry. Repeat for queued, pending and consumed controls.
- Cover automatic release with no per-request deadline, repeated shutdown during/after release, a worker that has already failed, several batches each below their own send deadline but above the total budget, and expiry with unfinished logs/spans/metrics. Assert typed Drain_deadline, accounting and no later successful replacement.
- Successful explicit shutdown must retire the worker before borrowed client cleanup; latch collector receives to prove there are no HTTP sends after ending. Preserve successful release-hook ordering and uncertain-batch at-least-once recovery tests.
- Door SIGTERM/stop fixtures provide the highest acceptance boundary. Their application teardown must finish within the configured total budget plus a bounded scheduler guard, including a stalled collector. Use controlled clocks/latches where available; outer test timeouts are deadlock guards, not evidence that the implementation timeout fired.
- Privacy regressions cover collector 503, malformed secret headers, pre/post-head transport failures and callbacks. Assert sanitized error rendering and never raw credentials or collector payload. Names cite new IDs; prior lifecycle/context IDs remain regression owners.

## Out of Scope

An ambient telemetry interpreter, SDK replacement, synchronous QuickJS host bridge, provider retry/auth policy, exporter self-metrics, live Inn verification, exactly-once export, trace propagation headers, and changing application metrics opt-in. Native string-only span attributes are a documented limitation, not a verified Exergy migration prerequisite.

## Further Notes

- Audit 2026-10-04 at Ox `08c6fc8f`; relevant source unchanged at `72af4cde`. Existing ^notel-6m2q, ^notel-p4xe, ^notel-t8br and ^notel-1stb already promise context and lifecycle outcomes. New IDs specify untested transitions, not a duplicate exporter. No new compiled tests or live collector checks ran in the audit.
- Evidence: [span conversion:79–112](<../../../lib/otel/ox_otel.ml#L79-L112>), [release ownership:232–280](<../../../lib/otel/ox_otel.ml#L232-L280>), [consumed Flush/Stop and loop:309–349](<../../../lib/otel/ox_otel.ml#L309-L349>), [release finish:421–427](<../../../lib/otel/ox_otel.ml#L421-L427>), [shutdown admission/deadline:448–464](<../../../lib/otel/ox_otel.ml#L448-L464>), and [public ending contract:125–132](<../../../lib/otel/ox_otel.mli#L125-L132>).
- Existing coverage: [nested IDs:387–433](<../../../test/otel/run.ml#L387-L433>), [successful release:435–506](<../../../test/otel/run.ml#L435-L506>), [secret-header status failure:658–685](<../../../test/otel/run.ml#L658-L685>), and [Door SIGTERM tests:1299–1312](<../../../test/app/run.ml#L1299-L1312>). Earlier green gates established those historical slices, not the new budget/control cases.
- Settled ending policy: one explicit configured total budget and one immutable terminal result. The caller chooses its duration; no invented universal default is required. This deliberately removes ambiguous eventual-success versus caller-deadline behavior instead of carrying both contracts.
- No credential leak has been verified. Privacy additions are regression hardening of an existing promise. Closed metrics admission already rejects new points; worker retirement is an ownership repair, not evidence of a post-shutdown metrics leak.
- Result-derived fields are owned by the [observability extension](<../observability/01-observability.md>); context export and ending can land independently, then the Door integration covers their composition. Existing metrics support is in the [metrics capability](<../otel-metrics/01-otel-metrics.md>).

Verified 2026-10-04 (context slice):
[`inherited_context_on_spans_and_logs`](<../../../test/otel/run.ml#L974>) covers ^notel-nbvl, ^notel-uydw, ^notel-p11y, ^notel-jda9 and ^notel-dzpj; [`completion_fields_on_spans`](<../../../test/otel/run.ml#L1242>) covers ^notel-nbvl and ^notel-dzpj through the public exporter and local collector.
