---
status: ready
package: ox (Circuit_breaker)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# Circuit breaker

## Problem Statement

Scala Ox has a `CircuitBreaker`: count-based or time-based sliding windows of call outcomes, a failure-rate and a slow-call-rate threshold, an open state that drops calls for a wait duration, and a half-open state that lets a bounded number of trial calls decide whether to close. Ox has none, so every service rebuilds one from a counter and a sleep.

## Solution

`Ox.Circuit_breaker` in Scala Ox's configuration shape, over an injected clock, with typed outcomes.

## User Stories

1. As a service author, I want `Circuit_breaker.create : clock:_ -> config -> t` with `config` holding `failure_rate_threshold`, `slow_call_threshold`, `slow_call_duration`, `sliding_window : [ `Count of Capacity.t | `Time of Duration.t ]`, `minimum_calls`, `wait_open`, `half_open_timeout`, `half_open_calls`, so that every Scala Ox setting has a field. ^nbreak-xcbd
2. As a service author, I want `run : t -> (unit -> ('a, 'e) result) @ local once -> ('a, [> `Open | 'e ]) result` and `run_or_drop` returning `'a option`-shaped results, so that a dropped call is a typed outcome, not an exception. ^nbreak-kdzt
3. As a service author, I want `is_failure : ('a, 'e) result -> bool` in the config (default: every `Error`), and exceptions counted as failures and re-raised unchanged, so that the breaker follows the two-error doctrine. ^nbreak-1751
4. As a service author, I want `state : t @ read -> [ `Closed | `Open | `Half_open ]` (row 72's read-only observer), so that status reports can show it. ^nbreak-xvy0
5. As a kernel maintainer, I want the state machine tested on a mock clock for every transition and a stress case with many concurrent callers in half-open, so that exactly `half_open_calls` trial calls pass. ^nbreak-pk06
6. As a maintainer, I want the floor table's circuit-breaker row set to `have`, so that the floor check stays true. ^nbreak-fuq4
