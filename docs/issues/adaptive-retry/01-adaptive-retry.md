---
status: ready
package: ox (Retry)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# Adaptive retries

## Problem Statement

Scala Ox's `AdaptiveRetry` shares a token bucket among callers: each retry costs tokens, each success refills, and when the bucket is empty retries stop, so a failing dependency is not retried into the ground by every caller at once. `Ox.Retry` retries each call on its own schedule.

## Solution

`Ox.Retry.Adaptive`: a shared bucket and a `retry` that pays for each retry and refunds on success, composed with the existing `Schedule` and `Retry.policy`.

## User Stories

1. As a service author, I want `Adaptive.create : bucket_size:Capacity.t -> failure_cost:int -> success_reward:int -> t` and `Adaptive.retry : t -> clock:_ -> ?policy:_ -> _ Schedule.t -> (unit -> ('a, 'e) result) @ local -> ('a, 'e) result`, so that retries share a budget across callers. ^nadapt-soby
2. As a service author, I want `should_pay_failure_cost : ('a, 'e) result -> bool` (default: every failure pays), so that a failure that is not the dependency's fault does not drain the bucket. ^nadapt-e6wv
3. As a service author, I want an empty bucket to return the last `Error` at once without sleeping, so that a broken dependency fails fast. ^nadapt-d5fi
4. As a kernel maintainer, I want the bucket's state behind `Ox.Mutex` (row 65) or an `Atomic`, mock-clock tests for pay, refund and exhaustion, and a stress case of many fibers sharing one bucket, so that the budget holds under concurrency. ^nadapt-lo33
5. As a maintainer, I want the floor table's adaptive-retries row set to `have`, so that the floor check stays true. ^nadapt-zeti

6. As a Service author, I want the policy for an identified non-idempotent retry operation to state when repetition is safe, so that partial success cannot silently duplicate an external effect. ^safe-o2b6
7. As an agent, I want operation-specific deduplication, reconciliation or refusal of retry used where needed, so that an HTTP verb, function name or result type is not mistaken for idempotency evidence. ^safe-a5mq
8. As a maintainer, I want timeout-after-commit and partial-success retry tests at an existing operation interface, so that the policy is verified against the failure window that motivates it. ^safe-3o27
9. As a reviewer, I want retry budgets and scheduling kept separate from replay safety, so that adaptive-retry work is neither duplicated nor credited with a guarantee it does not provide. ^safe-s51t
