---
status: completed
package: eta_test
consumer: every Leash test seam (AGENTS.md "Test seams")
---

# Test: Eio_mock plus Exit assertions

## Problem Statement

Tests need a deterministic clock, fakes for the operating system, and assertions on Causes, without a second runtime.

## Solution

`eta_test`: helpers over `Eio_mock` and Alcotest — a runner that provides a mock clock and stdenv, assertions on `Exit` and `Cause`, a fiber census, and a way to advance virtual time while a program is running.

## User Stories

1. As a test author, I want `Eta_test.run f` to run `f` under `Eio_main.run` with a mock clock and mock stdenv in scope, so that a test needs no boilerplate. ^ntest-6du6
2. As a test author, I want `Eta_test.advance clock d` to move virtual time and let sleepers wake before returning, so that "after 30 minutes" is one call. ^ntest-4227
3. As a test author, I want `Eta_test.fork_run` to start a program in a fiber, return a handle, and let me advance time then await its `Exit`, so that timeouts and schedules are testable mid-flight. ^ntest-ckt1
4. As a test author, I want Alcotest testables for `Cause` and `Exit` with structural equality ignoring backtraces, so that failures can be asserted precisely. ^ntest-190d
5. As a test author, I want `assert_no_fibers_left` after a concurrent test, so that leaked fibers fail the test. ^ntest-8ug3
6. As a test author, I want a scripted `Eio.Flow` pair (source/sink) helper, so that protocol code is tested against canned bytes. ^ntest-knpg
7. As a test author, I want a helper that builds a fake `Eio.Process.mgr` recording spawns and returning scripted exits, so that supervision logic is tested without real processes. ^ntest-0b6v
8. As a kernel maintainer, I want `eta_test` to depend on `eta`, `eio`, `eio_main`, `eio.mock` and `alcotest` only. ^ntest-n53y

## Implementation Decisions

- Thin: no test runtime of its own; `Eio_mock.Clock`, `Eio_mock.Flow`, `Eio_mock.Backend` are the machinery.
- Fake process manager: implement the `Eio.Process.mgr` class/record shape the pinned Eio exposes, with a script of exits and a log of spawn arguments including inherited fds.

## Testing Decisions

- Self-tests under `test/test/` covering each story with a trivial program.

## Out of Scope

Property testing, fuzzing, a fake HTTP server (the http spec brings its own).

Verification: `nix develop -c dune build @install`, `nix develop -c dune test test/test`, and `nix develop -c dune test` pass.
Coverage: eight `test/test` cases cite and exercise all eight `ntest-*` story IDs.
