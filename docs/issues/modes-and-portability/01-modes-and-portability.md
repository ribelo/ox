---
status: completed
package: every eta-next package
consumer: Leash (all milestones): the API must not need reshaping later to connect domains, parallel work, or local closures
---

# OxCaml modes and portability pass

## Problem Statement

ADR-0005 says OxCaml features are used wherever they earn a guarantee or speed, decided proactively. Rows 0–8 shipped with no mode annotations. Before Leash builds on the signatures, decide for each public signature what modes it carries, so that a later need — a parallel worker over `Eio.Domain_manager`, a non-escaping callback, a zero-allocation hot path — connects without an API rewrite. The constraint is real: Eio's `Switch.run`, `Fiber.fork`, `Fiber.pair`, `Fiber.first` take global closures (spike, ADR-0002), so a closure that eta-next forwards to Eio cannot be `local`.

## Solution

One pass over every `.mli` with a written decision per signature, applied consistently: `local` on closures the function runs in the current fiber and never stores; `portable` on the pure modules so they may cross domains; explicit single-domain documentation on the fiber-local and mutable ones; `[@zero_alloc]` where a benchmark shows it matters; and a short guide recording the rules so future signatures follow them.

## User Stories

1. As a kernel maintainer, I want a table in `docs/modes.md` listing every public function with its closure arguments and the decision (`local` or global, with the reason: run in place vs forwarded to Eio or stored), so that the rule is visible. ^nmodes-d2rn
2. As a service author, I want closures that eta-next runs in the calling fiber and does not retain — `Retry.retry`/`repeat` bodies, `Timeout.timeout` bodies if run in place, `Resource.acquire_release`'s `acquire`, `Scope.run`'s body if Eio's `Switch.run` accepts it, `Logger.span`'s body, `Context.with_fields`'s body — annotated `@ local`, so that I may pass stack-allocated closures. ^nmodes-8t8v
3. As a service author, I want closures eta-next forwards to Eio fibers or stores (`race`, `par`, `all`, `with_background`, `Supervised.start ~spawn`, `Listener.run ~handler`, `Correlator.create ~read/~write`) documented as global with the Eio constraint named, so that the asymmetry is explained, not mysterious. ^nmodes-8y46
4. As a service author, I want the pure modules — `Duration`, `Schedule`, `Cause`, `Exit`, `Interrupt_id`, `Eta_json`, `Eta_schema`, `Status` — declared `portable` (values and functions), so that they can be sent to another domain without wrappers later. ^nmodes-6pqn
5. As a service author, I want `Logger`, `Context`, `Correlator`, `Supervised`, `Listener` and `Child` documented as single-domain (their state is fiber-local or unsynchronised), with the rule that a future parallel package must create its own instances per domain, so that no one tries to share them. ^nmodes-yp1i
6. As a kernel maintainer, I want `[@zero_alloc]` asserted on `Duration` arithmetic and `Schedule.step`, and a benchmark under `bench/` for the correlator's call path with its allocation count recorded, so that hot paths are known rather than assumed. ^nmodes-78o3
7. As a kernel maintainer, I want the pass to change no behaviour: the full test suite passes unchanged, and any signature change that a test needs is a mode annotation only. ^nmodes-63rb
8. As a kernel maintainer, I want `docs/modes.md` to end with the three rules for future signatures (run-in-place closures are local; forwarded or stored closures are global and say so; pure modules are portable), so that a new package follows them without asking. ^nmodes-o66p
9. As a kernel maintainer, I want any place where the pinned Eio's signatures block an annotation that should exist recorded in `docs/modes.md` as an upstream gap with the exact function, so that it can be revisited when Eio's OxCaml fork adds modes. ^nmodes-cikk

## Implementation Decisions

- Work from the pinned Eio's actual signatures (`/home/ribelo/.cache/opam/5.4.0+ox/lib/eio`); try each `local` annotation and keep it only if it compiles against Eio.
- `portable` on a module means all its values are portable and it holds no mutable state; verify with the compiler, not by reading.
- Do not introduce `unique`/`once` on resource handles in this pass; note candidates (`Child.stop`, `Correlator.close`) in the guide for a later decision.

## Testing Decisions

- The existing suites unchanged (story 7); a compile-only test that sends a `Schedule.t` and a `Cause.t` through `Eio.Domain_manager.run` to prove portability (story 4).

## Out of Scope

Parallelism itself (`eta_par` comes with a consumer); unboxed types in public APIs; rewriting Eio.

Verification: `nix develop -c dune build @install`, `nix develop -c dune test`, and `nix develop -c dune build @fmt` passed for the full tree; `test/modes/portability.ml` ran on Eio domains and `bench/correlator_alloc.ml` measured 291.03 allocated words/call.
Verification: `docs/modes.md` records all closure decisions and pinned Eio/tooling gaps; unrestricted stored callbacks prevent arbitrary portable `Schedule.t`, and compiler-rejected allocations prevent a truthful `Schedule.step [@@zero_alloc]` without redesign.
Further note: row 16 (`^nnoschema-ttb5`) removed `Eta_schema` and `Eta_schema_yojson`; the rows and portability claims this pass made for them went with the packages, and `docs/modes.md` records that in their place. Nothing else this pass decided changed.
