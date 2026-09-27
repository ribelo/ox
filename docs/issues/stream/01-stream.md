---
status: completed
package: none (stdlib, eio; test-only eio.mock and alcotest)
consumer: Pie (PulseAudio capture, Codex Realtime, owned test fixtures)
---

# Stream: use Eio and Seq, do not restore eta_stream

## Problem Statement

Row 27 proposed pull streams and a lossy Mailbox from a package-reference count. That does not establish an uncovered operation. Pie needs ordered audio delivery, explicit admission limits, typed terminal outcomes, and inclusive stopping of realtime event consumption; the old blueprint operators are not themselves requirements.

## Measurement

Measured the read-only Pie checkout at commit `af9410b32eeb8070b6b7c0054fab56a821c8024c`. Its tracked OCaml sources are under `packages/pie`. Searched `*.ml` and `*.mli` for `Eta_stream`, `Stream_eio`, `Mailbox`, `Drain_counter` and aliases, including `module Stream = Eta_stream` in [Codex Realtime](/home/ribelo/projects/ribelo/pie/packages/pie/stt/codex_realtime.ml#L5). Excluded `.opam-eta-src`, `_build`, `.reference`, scratch files and vendored tests. Pie's own tests are counted separately; dependencies in Dune are not operation counts.

Counts below are qualified symbol occurrences, not line counts. Production has **17 operation references across seven operations**, two type annotations, and one alias declaration. Owned tests have **60 operation references**; **25** are the Eio adapter, all test-only. There are **zero Mailbox, Drain_counter, file-adapter, merge, parallel-stream, schedule, retry, timeout or generator uses** in either group.

| v1 operation | Production | Owned tests | Direct-style replacement / decision |
| --- | ---: | ---: | --- |
| `Stream.t` | 2 | 0 | Consumer-owned `unit -> ('a option, 'err) result` pull function for fallible input; `'a Seq.t` for finite pure data. Not a new Eta type. |
| `Stream.map` | 3 | 0 | `Seq.map` for pure sequences, or map `Ok (Some value)` after a typed pull. PCM conversion and frame decoding are ordinary calls. |
| `Stream.from_queue` | 2 | 0 | Consume the owner's FIFO; `Eio.Stream.take` for a live channel. For close/error/admission semantics, use the existing consumer session state plus `Queue`, `Eio.Mutex` and `Eio.Condition` (recipe below). Bare Eio.Stream is not a closeable queue. |
| `Stream.tap` | 1 | 0 | Update audio accounting when dequeuing, under the same lock as admission. No observer operator. |
| `Stream.take_until_effect` | 2 | 0 | Receive/decode one frame, fold that frame, evaluate the stopping predicate, then stop when true. Inclusive, unlike `Seq.take_while`; no speculative next receive. |
| `Sink.fold_effect` | 3 | 0 | Tail-recursive direct result-returning loop. On callback error, return immediately without another pull. |
| `run` | 3 | 0 | Call the loop with its explicit source and accumulator. No interpreter. |
| `run_for_each` | 3 | 4 | The same loop with a unit accumulator; synchronous callbacks can suspend through Eio. |
| `run_fold` | 0 | 3 | `Seq.fold_left` for pure fixtures; result-returning loop for typed failures. |
| `Stream.from_iterable` | 0 | 6 | `List.to_seq`. |
| `Stream.from_effect` | 0 | 7 | A lazy single pull thunk; blocking fixture reads call `Eio.Stream.take`, never-ending fixtures await an unresolved promise. |
| `Stream.succeed` | 0 | 4 | `Seq.return` (or `Ok (Some value)` from a one-shot pull). |
| `Stream.concat` | 0 | 4 | `Seq.append` for pure fixtures. Recursive queue fixtures become one `take` per pull, without rebuilding a stream. |
| `Stream.flat_map` | 0 | 4 | `Seq.flat_map` for pure fixtures; the actual four uses are the recursive queue-fixture construction above. |
| `Stream.fail` | 0 | 1 | Pull thunk returning `Error error`; not an exception and not EOF. |
| `Stream.map_effect` | 0 | 1 | Direct callback on each pull, propagating `Error` before any subsequent input. |
| `Stream.filter` | 0 | 1 | `Seq.filter` for pure fixtures or continue the direct pull loop when rejected. |
| `Eta_stream_eio.Stream.from_eio_stream` | 0 | 25 | Pull `Eio.Stream.take` directly. This adapter had no EOF semantics; scope cancellation still ends the fixture. |

Production evidence: [Pulse source and map](/home/ribelo/projects/ribelo/pie/packages/pie/pulse/client.ml#L498-L512), [record sink](/home/ribelo/projects/ribelo/pie/packages/pie/commands/record.ml#L180-L195), [meter sink](/home/ribelo/projects/ribelo/pie/packages/pie/commands/meter.ml#L1-L20), [PTT sink](/home/ribelo/projects/ribelo/pie/packages/pie/ptt_loop.ml#L254-L277), [realtime decode/folds](/home/ribelo/projects/ribelo/pie/packages/pie/stt/codex_realtime.ml#L658-L796), [audio send fold](/home/ribelo/projects/ribelo/pie/packages/pie/stt/codex_realtime.ml#L943), and [audio admission/accounting](/home/ribelo/projects/ribelo/pie/packages/pie/stt/codex_realtime.ml#L991-L1105).

### What v1 offered beyond this use

The inventory command was `git ls-tree -r v1 --name-only -- lib/stream lib/stream_eio test/stream test/stream_eio` (the same stream-prefix paths as filtering the full tree). Inspected interfaces with `git show v1:lib/stream/eta_stream.mli`, `git show v1:lib/stream_eio/eta_stream_eio.mli`, and `git show v1:lib/stream_eio/file.mli`.

The v1 tree includes the stream implementation/interface, internal mailbox and drain-counter modules, benchmarks, three ADRs and README; the Eio adapter/interface and file-error module; and separate stream and stream_eio test suites. Its public surface includes constructors, maps/filters/taps, changes/deduplication, zips, schedules/repeat/retry/timeout, take/drop/scan/grouping, concatenation/flat-map/merge/parallel flat-map, queue/producer adapters and tracing names; sinks and runners; a lossy Mailbox with dropped-count and batching; a Drain_counter; and Eio queue/file adapters. None of the unmeasured surface is pulled into eta-next. V1 is interface/behavior evidence, not implementation material for an effectful port.

## Solution

**No eta_stream or eta_stream_eio package is warranted by the measured uses. Close row 27 with this verdict.** Stdlib sequences, direct result loops and Eio synchronization cover them. Do not add a generic pull abstraction, closeable-channel library, sink language or compatibility facade merely to preserve v1 spellings.

The distinction matters: `Eio.Stream` supplies bounded blocking FIFO delivery, not close, typed failure, nonblocking offer, byte accounting or lossy overflow. Pie already owns the latter admission/lifecycle state. The [Pulse producer](/home/ribelo/projects/ribelo/pie/packages/pie/pulse/client.ml#L148-L175) **fails recording on overflow**, rather than dropping an audio item, and the [realtime producer](/home/ribelo/projects/ribelo/pie/packages/pie/stt/codex_realtime.ml#L1059-L1093) rejects over-budget offers. Neither pulls a lossy Mailbox. Moving those policies to a generic kernel would separate them from the byte and capture budgets they must update atomically.

## User Stories

1. As Pie's migration author, I want ordered lazy audio/event pulls and result-returning folds, including the terminal realtime frame, so that replacing blueprint operators does not over-read, hide failure or change callback ordering. ^nstream-a7k2
2. As Pie's capture owner, I want bounded Eio delivery and cancellation-owned producers/readers, so that a slow or stopped consumer cannot grow the queue or leak a fiber. ^nstream-b4m8
3. As Pie's audio session owner, I want explicit fail-fast admission, immutable PCM snapshots and a typed terminal outcome that follows buffered data, so that overflow, finish and cancellation remain distinct without a stream package. ^nstream-c9r3

## Implementation Decisions

- Pure fixture operators use `Seq`; live sources are single-consumer pulls and are never memoized or traversed twice. A result loop matches `Error e`, `Ok None`, or `Ok (Some x)`. It calls the sink before the fallible predicate (matching v1), emits the triggering frame, and does not pull again after stop or error. The realtime predicates currently cannot fail, but the migration must not turn their inclusive stop into an exclusive filter.
- Keep producer fibers and source resources in an explicit owner switch. A loop returning does not cancel an independently forked producer: use `Eio.Fiber.first` for a producer/consumer lifetime race, or existing Eta scoped concurrency. This is lifetime selection, not Eta's first-success race. Let cancellation and defects propagate; do not turn them into EOF. Finalizers run during scope settlement.
- Live unclosed test channels need only `Eio.Stream.create capacity`, `add`, `take`; these already provide backpressure. The application can also express a terminal event as an explicit sum when its producer may wait to publish it. Do **not** use a sentinel on a full queue for Pie's synchronous close.
- For Pulse and realtime audio, keep the existing session admission record, substituting a stdlib FIFO and Eio synchronization for Eta.Queue: under one mutex, validate open/failed/closed state and item/byte budgets, copy accepted bytes to an immutable string, enqueue and update counters. Broadcast the condition after admission or state change. Reading waits on that condition in a mutex-protected predicate loop, dequeues/accounting first, and only then returns the sticky terminal result when the FIFO is empty. Close changes state and broadcasts, consumes no capacity, and is first-terminal-wins. Realtime's reject-and-continue policy and Pulse's fail-and-detach policy remain in their callers. The test recipe uses concrete PCM/session state, not a reusable stream API.
- Eio.Stream alone does not provide the previous bullet. The combination of existing consumer-owned admission state, stdlib Queue, Eio.Mutex and Eio.Condition does. The lock covers both state and FIFO, avoiding a lost wakeup or a check-then-offer race. All accesses must go through that owner; do not mix unlocked Queue operations or raw systhread callbacks with Eio waits. Cross-thread producers must marshal to an Eio owner first.
- A cancelled wait releases the lock but does not implicitly close the session; its owner settles/cancels the source. On normal finish buffered chunks drain before EOF; on failed finish they drain before the typed error. Pulse's detached-channel behavior and realtime's capture-wide budget remain consumer responsibilities.
- No raw effect is introduced. ADR-0006 permits a local-token, one-fiber generator when a measured consumer needs retained continuations; none here does. Eio owns all suspended continuations in this recipe, so no local-token implementation is needed.

## Testing Decisions

Executable migration probes live in [test/stream/run.ml](../../../test/stream/run.ml), with no installed library. They demonstrate the replacement contracts, not a migration of Pie or a new general-purpose queue.

| Story | Tests |
| --- | --- |
| nstream-a7k2 | Lazy Seq construction/map/filter/append/flat-map; inclusive stop with no next pull; source and callback typed failures; sink-before-predicate ordering. |
| nstream-b4m8 | Capacity-one FIFO blocks a second producer add; a stopped consumer cancels a blocked producer and runs cleanup; a cancelled empty read does not steal the next item. |
| nstream-c9r3 | PCM snapshot and byte/item admission limits; rejected data never enters FIFO; clean/failed close on a full FIFO; close wakes an empty reader; first terminal wins; cancellation does not poison the mutex or later delivery. |

Verification: all six story-linked probes passed. Full-tree `dune build @install`, `dune test`, and `dune build @fmt` passed; the first formatting run found one missing blank line in the new Dune stanza, corrected before the passing rerun.

Deterministic Eio mock scheduling and promises establish ordering, not real sleeps. The three full-tree gates are `dune build @install`, `dune test`, and `dune build @fmt`, all run through `timeout 900 nix develop -c env DUNE_BUILD_DIR=_build_stream dune ...`.

## Out of Scope

Modifying Pie; shipping a compatibility layer; copying v1 effectful code or vendored tests; generators; lossy Mailbox, drain counters and unused combinators. A future measured consumer may pull a genuinely missing operation, with a new story. Row 27 is complete when this decision and its executable probes pass, not when Pie migrates.
