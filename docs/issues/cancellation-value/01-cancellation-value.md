---
status: completed
package: ox (spike), docs
consumer: every consumer (Ox-internal; ADR-0010)
---

# Spike: cancellation as a value, termination as the exception

## Problem Statement

Eio has one mechanism for two things: `Eio.Cancel.Cancelled` is both an expected, voluntary interruption (a deadline, a user's stop) and an implicit teardown (a sibling failed). Because it is an exception, any wide handler swallows it (`raw-concurrency-gate` story 3 can only refuse the pattern). Jane Street's `await` separates them: `Cancellation.t @ local` tokens for expected interruption, whose operations return `Or_canceled.t` (`Canceled | Completed of 'a`) and never raise, and `Terminator.t` for implicit termination, which raises.

## Solution

A spike, not a change: decide whether Ox's expected interruptions (timeouts, `request_stop`, `race` losers, `Channel` operations under a deadline) should return a typed `Canceled` from a local cancellation token, leaving Eio's exception for termination only, and what that does to the Cause tree (ADR-0002's `Interrupt`).

## User Stories

1. As a kernel maintainer, I want a prototype of `Ox.Cancellation.with_ : (t @ local -> 'a) @ local once -> 'a` and one operation (`Channel.receive ~cancel`) returning `[> `Canceled ]` without raising, over Eio, so that the shape is tested on our runtime. ^ncancel-58b3
2. As a kernel maintainer, I want the spike to answer: does a token-cancelled operation compose with `Scope.supervised_error` and `Concurrent` without a second cancellation model (ADR-0001's reason for leaving v1), so that the answer respects the ADR it could break. ^ncancel-yqo2
3. As a kernel maintainer, I want the spike to state which current `Interrupt` causes become typed failures and which stay interruptions, with the Door's exit codes for each, so that consumers' behaviour change is known. ^ncancel-cmec
4. As a maintainer, I want the outcome recorded as an ADR (adopt, adopt for named operations only, or reject with reason), so that nobody re-opens it without new evidence. ^ncancel-li9g

## Out of Scope

Any change to consumers.

## Verification

2026-10-04: ADR-0011 records the outcome — reject the recoverable token, keep typed boundary outcomes (`Timeout`) and Eio teardown. Prototype sources and the runner are in `spike/` (`nix develop -c sh docs/issues/cancellation-value/spike/run.sh`): 18/18 runtime, 2/2 Eio-view, 12/12 Door-mapping checks, 4/4 refused compiles, on 5.4.0+ox with Eio 1.6.
