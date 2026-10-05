---
status: ready
package: ox
consumer: every consumer (Ox-internal; ADR-0010)
---

# Fork bodies and releases are `@ once`

## Problem Statement

A resource handed to a fiber or to a release callback can also be used by the code that handed it over, or by a second fiber, and the compiler cannot tell: every Ox and Eio closure parameter is `many`. Row 57's shared TLS buffer is this class. Eio's parameters stay legacy (ADR-0010), so Ox has to state the mode itself.

## Solution

`Ox.Once.guard` converts a `once` closure into the `many` closure Eio needs, behind a one-shot flag that makes the cast unobservable. The fork, release and concurrent-branch boundaries listed below take their one-shot callbacks `@ once`, so a callback can own a `unique` value. The change is additive: a `many` closure is accepted where `once` is expected.

## User Stories

1. As a kernel maintainer, I want `Ox.Once.guard : (unit -> 'a) @ once -> (unit -> 'a) @ many` as the only place `Obj.magic_many` is called, raising `Invalid_argument` on a second call, so that affine-to-many adaptation is one audited function. ^nonce-ldtz
2. As a service author, I want `Scope.fork`, `fork_daemon`, `fork_error` and `fork_error_daemon` to take `@ once`, so that a value can be moved into exactly one fiber and a second use is a compile error. ^nonce-r7mi
3. As a service author, I want `Scope.on_release : 'e t -> (unit -> unit) @ once -> unit`, and `Resource.use_in_scope`'s release `@ once`, so that a release can own what it frees and the body cannot also free it. ^nonce-4jzx
4. As a service author, I want `Concurrent.par`, `both`, `all`, `race`, `race_first` and `with_background` branches `@ once`, including affine branch lists where needed; the per-item `for_each` mapper, `Actor.create ~on_stop` and `Supervisor` start functions remain `many` where they are invoked repeatedly, so that each callback's mode says how often it runs. ^nonce-nngp
5. As a kernel maintainer, I want in-place callbacks (`Rate_limiter.run`, `run_or_drop`, `Resource.use_in_scope`'s acquire, `Retry.retry`/`repeat`'s thunk where it is called once per attempt only if that holds) to be `@ local once` exactly where the implementation calls them at most once, so that `docs/modes.md` lists the linearity of every closure parameter. ^nonce-lrzq
6. As a kernel maintainer, I want compile-fail cases under `test/ownership/compile_fail/` (a unique value moved into two forks, used after a release took it, captured by raw `Eio.Fiber.fork`) and their compiling controls, run by a `check.sh` like `test/caps/compile_fail`, so that each refusal is pinned. ^nonce-mjpe

## Implementation Decisions

```ocaml
let guard (f : (unit -> 'a) @ once) : unit -> 'a =
  let f = Obj.magic_many f in
  let used = Atomic.make false in
  fun () -> if Atomic.exchange used true then invalid_arg "Ox.Once" else f ()
```
Verified on 5.4.0+ox (ADR-0010): moving a `unique` record into one `Ox` fork compiles; into two forks, after a release, or into raw `Eio.Fiber.fork` is refused. `docs/modes.md` gains a linearity column.

The guarded affine-to-many adapter accepts global callbacks only. Directly invoked local-once callbacks need no locality conversion. The proposed `%identity` bridge into Eio cancellation protection and RW mutex operations is not admitted: synchronous joining does not preserve collector roots while a callback waits. A heap guard can be the sole reference to a stack-local callback, whose heap-valued captures are then not traced through that heap edge. Any future local bridge must establish collector rooting throughout pre-entry suspension, execution, cancellation and region retirement, in addition to the exact provider lifetime contract. Fresh source pins and complete typed-body verification cannot replace that runtime invariant. Neither a locality conversion nor an arbitrary legacy callback runner is exported (safe-4zis, ncrit-oa64).

The opt-in provider lane is experimental, not default adoption (^nonce-lrzq, ^nonce-mjpe). It solves upstream Eio 1.6's exact release archive (SHA256 c1f04986b401094176494863dde1ca9b292b59fdc679a9d7023e558d80fb5b15; source commit 1fc0efa41ccfb3818b09f54feec90ec29b47f1b6) as eio/eio_posix/eio_linux/eio_main 1.6+ox-local-once.1. One zero-context four-file patch (SHA256 320bf57c259ed34c43306f83662a788eb1c721522bca4ec7a5f9806719e5cd84) changes only three implementation parameter modes, the two public Cancel.protect/Mutex.use_rw callback signatures, and one non-tail annotation. It introduces no cancellation, locking, cleanup, Switch, sub, deadline, or callback-storage algorithm. Results remain global; cancelled acquisition may drop the callback without entering it. The provider's native typed bodies, rather than a cast or an interface shim, establish the local-once boundary.

The experimental exported opam repository and Nix-native shell/check use a genuinely resolved compiler/provider/dependency scope and rebuild the complete 17-package Ox reverse closure. Checksummed source packaging sets the exact project/package version without changing the semantic patch; the locked repository supplies source-native Dune 3.22.2+ox (CLI 3.22.2) and Alcotest 1.9.0+ox. Provider source hashes, native/bytecode libraries, private modules, stubs, metadata versions, compiler and package origins are checked before mode controls. No inherited OPAM package paths or old-CMI fallback enter that lane. The ordinary upstream-1.6 repository, default shells, installer and shared switch are unchanged. Default builds never invoke the opt-in @eio-local-once alias.

Admission requires authored-MLI/native-ML paired controls, physical Cmm alloc_local evidence, rejected reuse/storage mutations of genuine provider bodies, a fresh external consumer solve using the exported recipe, and the same 14 GC/cancellation/exception/root-retirement controls on Mock, POSIX and Main Linux. Both independently solved native acceptance scopes passed these controls and 42 backend cases each; the full 22-package Ox closure rebuilt, with all 17 affected consumers checked and the external executable run. This is experimental recipe acceptance, not adoption. The runtime bound is single-domain native Linux, including pre-entry queue suspension and cancellation: no heap-to-local edge, multicore handoff, universal zero-allocation claim, Windows/Darwin runtime proof, deadline adoption or general locality bridge is admitted.

## Testing Decisions

Compile-fail harness (story 6); the existing `test/core` and `@stress` suites must pass unchanged, since the change is additive.

## Out of Scope

Owned handles (`owned-handles`), the gate on raw Eio (`raw-concurrency-gate`), local scopes (`local-scope`).
