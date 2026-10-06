# ox-execution-context

**Dormant:** explicit audit only; incomplete ordinary consumer evidence prevents activation. ^safe-9ved ^safe-sr6e

One bounded compiler-UID visitor covers two concrete defects: sleep/join/semaphore waits block an authenticated Eio owner callback; Eio effects in executed Ox_blocking positional callbacks run without an Eio handler. Hooks remain caller-context. Eio_main.run in native code establishes a legal new owner.

Owner entries are Eio_main/Eio_linux/Eio_posix.run and Ox_test.run. Waits are Unix.sleep/sleepf, Thread.delay/join, Domain.join and Counting.acquire. Descriptor read/write are outside this catalogue. Worker entry is Ox_blocking.run/run_result, never a spelling match. Local aliases, closures and executed arguments are bounded; unresolved selected calls and exhausted horizons are named undecided, not certified clean.

The [violating pair](<../../test/lint/violating/execution_context.ml>) and [clean pair](<../../test/lint/clean/execution_context.ml>) have one [MI-first consumer probe](<../../test/lint/safety_execution_context/corpus.ml>): exact full observations, a bounded owner deadlock whose yielded sibling cannot release the awaited semaphore, and genuine native Eio yield raising Effect.Unhandled through Ox_blocking.run. These are not pool refusal or a generic effect/cancellation certificate.
