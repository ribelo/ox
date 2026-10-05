# ox-stdlib-lock

^nlintc-kdcl

## Definition

Stdlib mutex/semaphore creation and synchronous critical sections are legal. Report a known scheduler suspension while a Stdlib mutex or semaphore remains held. Track resolved acquire/release operations, aliases, immediate Fun.protect bodies and local helper calls. Creating a returned closure does not execute it under its creator's lock.

Release the lock before yielding, awaiting or performing known Eio IO, or use a fiber-aware lock for a genuinely suspending critical section. SQLite's C-state protection and IPC's synchronous table operations are correct without path exemptions.

Local helper traversal is memoized by the physical closure, incoming held-lock set
and canonical visible substitutions, and replays the outgoing lock state on a cache
hit. Different lock arguments therefore remain distinct. Helpers are not expanded
when no lock is held; repeated no-lock call diamonds do not create exponential work.
Compiled regressions cover distinct substitutions and cached release transfer.
^nlintc-j03j ^nlintc-kdcl

## What this does not cover

This is local typed control-flow analysis, not a whole-program lock proof. Branch states are joined conservatively; correlated branches may need a clearer release boundary. Opaque imported callbacks, foreign primitives and unlisted suspension APIs are not inferred. An unknown callback is not proof of suspension. Eio locks and shadowing local modules are not Stdlib locks.

[Violating fixture](<../../test/lint/violating/stdlib_lock.ml>) and [clean fixture](<../../test/lint/clean/stdlib_lock.ml>) pin unsafe suspensions and safe synchronous scopes.

Compiled negative fixtures belong to separate nested Dune projects, which the default gate does not descend into. The workspace still builds their typed evidence; explicit scans retain every finding, and exact-site regression tests fail if a fixture stops violating. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>) (^ncapslint-2606).
