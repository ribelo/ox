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

9. As a reviewer, I want `ox-catch-all` written in the two shapes the neighbours proved decidable statically — a handler that binds the cancellation and does not re-raise it (Trio's `ASYNC104`), and a bare `with _ ->` / `with exn ->` whose body does not re-raise the bound value (`ASYNC103`; detekt's `SuspendFunSwallowedCancellation` is the same check for Kotlin) — with the rule stated as "does not re-raise" rather than "is unsafe", and its false negatives written down. ^nrawc-p4kt
10. As a reviewer, I want `ox-fun-protect` written the way clippy's `await_holding_lock` is — a syntactic match for a suspending call inside the `finally` or `on_release` body, with an allow-list carrying a reason per entry — since neither OCaml nor Semgrep can type the body, and clippy ships exactly this approximation for the same hazard. ^nrawc-9mzb
11. As a maintainer, I want ox's existing `[@@alert mint]` made fatal by the compiler (`-alert @mint` in the root `dune`'s `env`, relaxed to `-alert -mint` in `lib/caps`, `lib/app`, `lib/test` and the `bin` entries, the same allow-list the gate already carries) plus a fixture asserting both the refusal and the alert text, so that the rule has a compiler surface beside the gate — the alert exists today and nothing makes it bite. Third-party values such as `Eio.Fiber.fork` cannot be alerted, which is why they stay story 1's job. ^nrawc-t5hq
12. As a maintainer, I want the gate to lint its own rule file — duplicate ids, a rule with no message, a rule whose pattern yields no identifier for the lexical fallback (which would silently disable the fallback), a rule id absent from the violating fixture, and a rule id absent from its documentation page — because the strongest invariant the gate already has is the fixed set of ids that must fire, and the doc and fallback sides of that triangle are unchecked. ^nrawc-x8bn
13. As a maintainer, I want it recorded in this spec that Semgrep's OCaml support is Experimental by Semgrep's own definition — no module-open resolution, no typed metavariables, limited pattern syntax, no OCaml page in its documentation — so that every rule here is written in the subset that tier allows and the lexical fallback carries the rest; ox's skip-handling (parse the JSON, rescan skipped files lexically, fail closed) is the most complete answer found anywhere and stays the pattern. ^nrawc-rj2v

## Implementation Decisions

Rule 4 cannot see types; it matches names, and its false negatives are accepted. Story 9's re-raise exemption is a statement-order condition inside a handler body, which the Experimental OCaml tier cannot express, so it is implemented as a lexical allowance with its accepted false negatives listed. Evidence for stories 9–13: [research/04-checkable.md](../usage-rules/research/04-checkable.md) and [research/05-neighbours.md](../usage-rules/research/05-neighbours.md). Rules 1 and 5 land after `once-forks`, `spawner` and `ox-mutex` provide the replacements.

## Out of Scope

Typing any of these (ADR-0010, "not expressible").
