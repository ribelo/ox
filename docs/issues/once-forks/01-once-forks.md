---
status: ready
package: ox
consumer: every consumer (Ox-internal; ADR-0010)
---

# Fork bodies and releases are `@ once`

## Problem Statement

A resource handed to a fiber or to a release callback can also be used by the code that handed it over, or by a second fiber, and the compiler cannot tell: every Ox and Eio closure parameter is `many`. Row 57's shared TLS buffer is this class. Eio's parameters stay legacy (ADR-0010), so Ox has to state the mode itself.

## Solution

`Ox.Once.guard` converts a `once` closure into the `many` closure Eio needs, behind a one-shot flag that makes the cast unobservable. Every Ox function that runs a callback at most once takes it `@ once`, so a callback can own a `unique` value. The change is additive: a `many` closure is accepted where `once` is expected.

## User Stories

1. As a kernel maintainer, I want `Ox.Once.guard : (unit -> 'a) @ once -> unit -> 'a` as the only place `Obj.magic_many` is called, raising `Invalid_argument` on a second call, so that the one unsafe mode cast in the tree is one audited function. ^nonce-ldtz
2. As a service author, I want `Scope.fork`, `fork_daemon`, `fork_error` and `fork_error_daemon` to take `@ once`, so that a value can be moved into exactly one fiber and a second use is a compile error. ^nonce-r7mi
3. As a service author, I want `Scope.on_release : 'e t -> (unit -> unit) @ once -> unit`, and `Resource.use_in_scope`'s release `@ once`, so that a release can own what it frees and the body cannot also free it. ^nonce-4jzx
4. As a service author, I want `Concurrent.par`, `both`, `all`, `race`, `race_first`, `for_each` and `with_background` branches `@ once`, `Actor.create ~on_stop` and `Supervisor` start functions left `many` where restarts call them again, so that each callback's mode says how often it runs. ^nonce-nngp
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

## Testing Decisions

Compile-fail harness (story 6); the existing `test/core` and `@stress` suites must pass unchanged, since the change is additive.

## Out of Scope

Owned handles (`owned-handles`), the gate on raw Eio (`raw-concurrency-gate`), local scopes (`local-scope`).
