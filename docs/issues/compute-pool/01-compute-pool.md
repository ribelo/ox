---
status: ready
package: ox (Compute)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# CPU-intensive work on other domains, with `portable` checked

## Problem Statement

Scala Ox runs CPU-intensive work on a dedicated pool so it does not starve the I/O threads. Ox runs everything on one domain; `Ox_blocking` moves blocking calls to systhreads of the same domain, which does not add CPU. Eio 1.6 has `Executor_pool` over `Domain_manager`, whose closures are legacy `nonportable`, so nothing stops a job from capturing a fiber's mutable state and racing on it.

## Solution

`Ox.Compute`: a pool of domains (Eio's `Executor_pool`) whose submit function requires the job to be `@ portable` and its result `@ portable`, so a data race across domains is a compile error. Capabilities stay behind: they cannot be captured by a portable closure (verified, `test/caps/compile_fail/portable.ml`).

## User Stories

1. As a service author, I want `Compute.create : sw:_ -> domain_mgr:_ -> domains:Concurrency.t -> t` and `Compute.run : t -> (unit -> 'a @ portable) @ portable once -> 'a`, suspending the calling fiber until the job finishes, so that CPU work leaves the I/O domain and its type proves it shares nothing mutable. ^ncpu-bxcb
2. As a service author, I want `Compute.run_result` for jobs returning `('a, 'e) result` with `'e` portable, so that typed errors cross the domain as values. ^ncpu-789n
3. As a service author, I want cancelling the caller to mark the job cancelled (checked by `Compute.is_cancelled` inside the job) and the caller to wait for it to stop, so that cancellation stays structured across domains. ^ncpu-dzic
4. As a service author, I want shared state across jobs expressed with `Ox.Mutex`'s branded data extended to domains (`Capsule`-shaped: data crosses as `portable`, access only under the lock), or refused, so that the only way to share mutable state is a typed one. ^ncpu-8t45
5. As a kernel maintainer, I want compile-fail cases (job capturing a `ref`, a capability, an `Eio` value) and a test running real work on two domains, so that the refusals and the speed-up are both pinned. ^ncpu-r5i3
6. As a maintainer, I want `docs/modes.md` and ADR-0009's single-domain caveat updated, and the floor table's compute-pool row set to `have`, so that the documents say where a domain is crossed. ^ncpu-peu5

## Implementation Decisions

`Executor_pool.submit` takes a nonportable closure; `Compute.run` requires `portable` and passes it on, which is sound (portable is a submode of nonportable). Results come back through Eio's promise and are `portable` by the signature.
