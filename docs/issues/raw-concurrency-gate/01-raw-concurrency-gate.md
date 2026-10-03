---
status: ready
package: ox_caps (gate rules), scripts/caps-gate
consumer: every consumer (Ox-internal; ADR-0010)
---

# Gate: no raw Eio concurrency, no Stdlib mutex, and the untypeable rules

## Problem Statement

Every mode guarantee in ADR-0010 is opt-in while a consumer can call `Eio.Fiber.fork` or `Eio.Switch.on_release` directly. Four other rules the doctrine states in prose are broken in the tree today and cannot be typed: `with _ ->` swallowing `Eio.Cancel.Cancelled` (5 in `lib/`), `Fun.protect` whose `finally` may suspend while cancelled (33), discarded `result`s (39 `ignore`/`let _ =` sites, e.g. `ws_client.ml:426`), and public `exception`s in `.mli`s (`ox_sql`, `ox_sql_dsl`, `tls_flow`) against ADR-0002.

## Solution

New Semgrep rules in `caps.yaml`'s gate, with the same lexical fallback and fixtures, applied to ox and every consumer.

## User Stories

1. As a reviewer, I want rule `ox-raw-concurrency` refusing `Eio.Fiber.fork*`, `Fiber.both/pair/all/any/first/List.*`, `Eio.Switch.run`, `Switch.on_release*` and `Eio.Mutex` outside `lib/ox`, naming the Ox replacement, so that ownership modes cannot be bypassed. ^nrawc-z6ev
2. As a reviewer, I want rule `ox-stdlib-mutex` refusing `Mutex.*`, `Condition.*` and `Semaphore.*` of the stdlib outside an `--allow` entry with a reason (`lib/sql/sqlite.ml`, which guards C calls contended by systhreads), and `lib/ipc/listener.ml`'s registry moved to `Ox.Mutex` or made lock-free, so that a domain-blocking lock cannot be held across a yield. ^nrawc-bzzr
3. As a reviewer, I want rule `ox-catch-all` refusing `with _ ->`, `| exception _ ->` and `| _ ->` arms of a `try` in `lib/` unless the arm re-raises `Eio.Cancel.Cancelled` first, and the five sites in ox fixed, so that an interruption is never turned into something else. ^nrawc-zkcj
4. As a reviewer, I want rule `ox-discarded-result` refusing `ignore` and `let _ =` applied to a call whose name is a known `result`-returning Ox function or ends in `_result`, with `Result.ignore_error`-style named discards as the escape, so that dropping a failure is visible. ^nrawc-efwv
5. As a reviewer, I want rule `ox-fun-protect` refusing `Fun.protect` in `lib/` (releases go to `Scope.on_release`, in-place cleanup to `Ox.Cancel.protect` from `ox-mutex`), so that a finalizer cannot be interrupted by the cancellation it is cleaning up after. ^nrawc-c96t
6. As a reviewer, I want rule `ox-public-exception` refusing `exception` declarations in `lib/**/*.mli`, and `Ox_sql.Error`, `Types.raise_error`, `Ox_sql_dsl.Error` and `Tls_flow.Tls_failure` made private with `result`-returning edges, so that ADR-0002 holds in the kernel. ^nrawc-u5gu
7. As a reviewer, I want rule `ox-obj-magic` widened to every `Obj.magic*` and allowed only in `lib/ox/once.ml`, so that the trusted mode casts stay one file. ^nrawc-68o2
8. As a maintainer, I want violating and clean fixtures for each rule under `test/caps/gate/`, and each consumer's current finding count recorded here before it migrates, so that the cost is known. ^nrawc-s4qm

## Implementation Decisions

Rule 4 cannot see types; it matches names, and its false negatives are accepted. Rules 1 and 5 land after `once-forks`, `spawner` and `ox-mutex` provide the replacements.

## Out of Scope

Typing any of these (ADR-0010, "not expressible").
