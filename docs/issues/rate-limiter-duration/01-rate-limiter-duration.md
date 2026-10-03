---
status: ready
package: ox (Rate_limiter)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# Duration rate-limiter algorithms

## Problem Statement

Scala Ox's duration algorithms limit operations by their whole execution span — how many may be *running* within a window — not only by start time. `Ox.Rate_limiter.algorithm` has no release hook, so it can only count starts.

## Solution

A release hook on the algorithm and duration variants of the fixed and sliding windows.

## User Stories

1. As a service author, I want `algorithm` to gain `release : now_ms:int -> unit`, called when the operation finishes by success, error, exception or cancellation, with the existing start-time algorithms ignoring it, so that an algorithm can count running operations. ^nrldur-eu2m
2. As a service author, I want `Duration_fixed_window` and `Duration_sliding_window` that count an operation from its start to its end, so that a slow dependency is protected by how much work is in flight. ^nrldur-i4j5
3. As a kernel maintainer, I want the release to run in a cancel-protected finalizer (`Ox.Cancel.protect`, row 65), so that a cancelled operation still returns its permit. ^nrldur-7dkn
4. As a kernel maintainer, I want mock-clock tests for each variant including an operation cancelled mid-flight, so that a permit is never leaked. ^nrldur-ey5k
5. As a maintainer, I want the floor table's duration-algorithms row set to `have`, so that the floor check stays true. ^nrldur-bbni
