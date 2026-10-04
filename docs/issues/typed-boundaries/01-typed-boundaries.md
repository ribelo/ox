---
status: ready
package: ox, ox_http, ox_ipc, ox_rpc, ox_sql, ox_blocking
consumer: Ox (ADR-0011: the option it chose)
---

# Every boundary Ox owns reports its outcome as a value

## Problem Statement

ADR-0011 rejected a recoverable cancellation token because it needs its own cancelled state and waiter list beside Eio's — a second cancellation model (ADR-0001). It chose the other option and named it: **translate the outcome of a boundary Ox itself owns**. Where Ox decided to cancel, Ox knows why, and can return a value instead of letting an exception travel into a caller who may swallow it.

Ox already does this in four places and nowhere else: `Timeout.timeout` returns `Error `Timeout`; `Actor.ask ?timeout` returns `Error `Timeout` with the actor undisturbed ([actor.mli:79-81](../../lib/ox/actor.mli#L79-L81)); `Select.timeout_clause` fires as an ordinary clause; `Ox_blocking.run_result_timeout` returns ``Timed_out`. `Channel.send`/`receive`, `Scope.await`, `Rate_limiter.run`, the HTTP, WebSocket, IPC and SQL waits and `Concurrent`'s losers have no such form: a deadline there is either written by the caller as `timeout (fun () -> ...)`, which is fine, or reached by cancellation from outside, which is an exception.

## Solution

One rule, applied everywhere it holds and stated in the interface of every blocking operation: **if the cancellation was decided by this operation, its result is a value; if it came from outside, Eio's exception propagates untouched.** No token, no cancelled bit, no waiter registry, nothing kept in step with Eio by hand.

## User Stories

1. As a kernel maintainer, I want the rule written once in `docs/why-ox.md` and in ADR-0011's consequences — an Ox-owned boundary gives a typed value, a foreign interruption stays an exception classified by `Scope.run` — so that the next agent does not reinvent a token. ^nbound-3ckq
2. As a service author, I want `?deadline:(clock * Duration.t)` on the blocking operations that lack it (`Channel.send`, `Channel.receive`, `Scope.await`, `Rate_limiter.run` and the waits row 83 adds) returning `[> `Timeout]` and leaving the structure untouched, as `Actor.ask` already does, so that a deadline is a value at every wait and not only at four of them. ^nbound-n1eo
3. As a service author, I want each blocking operation's `.mli` to state in one sentence who owns its cancellation: the typed outcomes it produces itself, and that any other interruption propagates as Eio's cancellation, so that the rule is checkable per function instead of only in prose. ^nbound-2s64
4. As a service author, I want `Concurrent.race` and `race_first` to report the losers' interruption where the Cause tree already carries it, rather than only suppressing it, so that "the loser was cancelled" is visible without reading Eio's internals. ^nbound-0xcj
5. As a service author, I want a program to be able to observe that a stop was requested (`Ox_app.stop_requested`, or a condition it can wait on) with no change to the Cause tree and no change to the Door's exit codes — ADR-0011's table stands: a recorded stop stays `Interrupt (Some id)`, exit 0 or 130 — so that a long loop can finish cleanly by choice instead of by exception. ^nbound-4oqe
6. As a kernel maintainer, I want the operations that must **not** get a typed form listed with the reason — anything whose cancellation is Eio's teardown, since translating that is the rejected token — so that the rule's edge is recorded rather than guessed. ^nbound-czpp
7. As a kernel maintainer, I want a test per operation: the deadline path returns the value and leaves the structure usable; an external cancellation of the same operation raises and is classified as `Interrupt`; the two are never confused. ^nbound-j4y5
8. As a maintainer, I want ADR-0011 and `docs/design/ox-floor.md` to cite this row as the adopted part of `await`'s idea, so that the ADR's chosen option has code behind it. ^nbound-c1zo

## Implementation Decisions

A deadline is implemented with the operation's own Eio clock wait, never by racing a sleep (`race` selects the first success). An operation that takes `?deadline` keeps its undeadlined form unchanged. No operation gains a cancellation token and none stores a cancelled flag: the only interruption state is the one Eio already has.

## Out of Scope

A recoverable cancellation token (ADR-0011 rejects it); changing what any current `Interrupt` means; the Door's exit mapping.
