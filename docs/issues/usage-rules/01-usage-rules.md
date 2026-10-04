---
status: ready
package: docs, scripts, ox_caps (gate)
consumer: Ox and every consumer: the agents that write them
---

# Rules an agent can check it followed

## Problem Statement

Every line of ox and of its consumers is written by agents; the human reviews interfaces. Three of the hard classes cannot be refused by the compiler (ADR-0010) — a swallowed `Eio.Cancel.Cancelled`, a finalizer that suspends while cancelled, a Stdlib mutex held across a suspension — and a fourth, timing, is reachable only by simulation (row 85). For those, documentation is the mechanism. Documentation an agent cannot verify it followed is decoration: `docs/caps.md` works because `scripts/caps-gate` decides, while the doctrine in `docs/why-ox.md` §4 was violated inside ox itself (public exceptions in `.mli` files, five catch-all handlers) for weeks with nothing noticing.

## Solution

Every rule carries its check: one page per rule with the wrong and the right code, a machine-readable index mapping each rule to the command that decides it, and one script an agent runs before committing that runs them all and names what failed.

## User Stories

1. As an agent writing ox or a consumer, I want `docs/rules/` with one short page per rule — what it forbids, the smallest wrong example, the right form, and the check that decides it — covering at least: do not catch `Cancelled` (no `with _ ->`); cleanup goes on the switch or inside `Cancel.protect`; no Stdlib mutex or blocking call in a fiber; no raw Eio concurrency; do not discard a `result`; no `exception` in an `.mli`; a handle is used where it is owned; a deadline is `timeout` and never `race` against a sleep; every `.mli` states cancellation and finalizer behaviour; a transport or concurrency change needs a simulation case (row 85). ^nguide-xwuf
2. As an agent, I want `docs/rules/index.yaml` giving for every rule its id, the paths it applies to, how it is enforced (`compiler`, `gate`, `test` or `review`) and the exact command that decides it, so that I can run the rules for the files I touched instead of reading prose and hoping. ^nguide-vka6
3. As an agent, I want `scripts/ox-check [PATH...]` to run every enforceable rule for those paths — the four gates, the gate rules of row 66, the compile-fail suites — printing one line per rule with pass, fail and the file, exiting non-zero on any failure, so that "did I do this right" is a command and not a judgement. ^nguide-j4m4
4. As an agent, I want each rule page to name what its check cannot see — the gate matches names, not types; the simulator does not control interleaving; `@ read` protects a value's own fields only — so that I do not read a pass as proof. ^nguide-lg1m
5. As a reviewer, I want a rule with no check marked `review` in the index and listed in one place, so that the set of things resting on a human's attention is short, visible and shrinking. ^nguide-svoi
6. As a kernel maintainer, I want the convention that every `val` in `lib/**/*.mli` states its cancellation, suspension and finalizer behaviour — Eio's own convention — and a check that fails on a new or changed `val` whose doc comment states none of it, and, for anything that can be cancelled midway, its **cancel safety** in tokio's three-valued form (safe to re-run, unsafe because data is lost, unsafe because progress is lost), so that the interface keeps being what a reviewer can trust. ^nguide-sxi4
7. As a maintainer, I want the five research reports commissioned on 2026-10-04 folded in — Eio community practice, OxCaml mode patterns, deterministic simulation, machine-checkable rules, and the rules of Scala Ox, Kotlin, Loom, Trio, Go and Rust — so that every adopted rule cites where it comes from and every rejected candidate is listed with its reason. ^nguide-yofs
8. As a maintainer, I want `AGENTS.md` to point at `scripts/ox-check` as the thing to run before committing, and the consumers' own agent instructions to do the same, so that one command is the contract in every repository. ^nguide-6tuu

9. As a kernel maintainer, I want ox to **write down the documentation contract Eio only practises**: Eio's `.mli` files state cancellation, finalizer and locking behaviour per function consistently, but the convention is nowhere written — not in its `HACKING.md` — so an agent cannot check itself against it. Ox states it, in one page, with the shape of the sentence and the check from story 6. ^nguide-2hvs
10. As a service author, I want a `docs/rules/uninterruptible.md` listing, per blocking operation ox actually packages (classic OCaml blocking I/O, Unix sockets, process pipes, subprocess waits), whether it is interruptible, destructively interruptible or uninterruptible, with its citation and the sanctioned escape (`Ox_blocking`), after Scala Ox's `abandonOnInterrupt` family and its tests, so that "this call cannot be cancelled" is a looked-up fact rather than a surprise. ^nguide-5bqc
11. As a maintainer, I want the rule pages written as **negative constraints with a command**, not as positive advice, and `AGENTS.md` rewritten the same way: the studies found that the rules agents follow are prohibitions, that positive directives can hurt, that compliance decays within a session, and that an instruction file alone does not raise success rates. Prose is a hint; the check is the rule. ^nguide-wd4p
12. As a maintainer, I want it recorded that no study was found isolating "rule plus check" from "rule as prose", so this row's central bet is stated as a bet, resting on ox's own evidence (the caps gate holds; the `why-ox.md` `4 doctrine did not) rather than on published measurement. ^nguide-q9sf

## Implementation Decisions

The pages are short on purpose: an agent reads one when a check fails, so each is a diagnosis, not an essay. The index is the single source — `scripts/ox-check` reads it, and a rule that is not in it does not exist. The compile-fail harness becomes table-driven — a file of `<case> <expected compiler message fragment>` rows — so a refusal is pinned by its *reason* and not only by a non-zero exit, and every "Refused" line of ADR-0010 gets a row (the ADR already quotes the compiler's wording). A rule enforced by the compiler cites the compile-fail case that proves it; a rule enforced by the gate cites its Semgrep rule id and fixture. `docs/caps.md` is already a rule page with a check and becomes the first entry by reference, not by being rewritten.

The five reports of 2026-10-04 are in [research/](research/): [Eio community practice](research/01-eio.md), [OxCaml mode patterns](research/02-oxcaml.md), [deterministic simulation](research/03-simulation.md), [machine-checkable rules](research/04-checkable.md), [the neighbouring ecosystems](research/05-neighbours.md). Each adopted rule page cites its report and the primary source behind it; rejected candidates stay in the reports' own section 3 rather than being re-argued here.

## Out of Scope

Rewriting `CONTEXT.md` or the ADRs; a documentation generator.
