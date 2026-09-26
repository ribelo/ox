---
status: completed
package: eta_app, eta (Concurrent), repository root
consumer: Leash milestone 1 (chrome-fuao: the control listener needs the status query before serve blocks)
---

# Review fixes after rows 0–8

## Problem Statement

Three findings from the coordinator's review of the delivered rows. `Eta_app.serve ~publish` hands the status query out only after `serve` has been entered, but Leash's control listener is a Service created before `serve` and needs the query in its deps; the shape is circular for the first consumer. `Concurrent.race` fails with `[> \`Concurrent of 'e Cause.t]`, a variant that does not compose with the caller's own error union. The repository has no `.ocamlformat`, so nothing is format-checked (the row-0 instruction to keep one was wrong: none ever existed).

## Solution

A status query composed as a plain value before serving; `race` failing with the Cause directly; a formatter configuration and a format gate.

## User Stories

1. As a service author, I want `Eta_app.status_query : (unit -> Status.t) list -> (unit -> Status.t list)` as a pure composer, and `Eta_app.serve ~sw : unit -> ('a, 'e) result` to only block until interrupted, so that a Service created before serving can hold the query. ^nfix-j678
2. As a service author, I want `Concurrent.race` to return `('a, 'e Cause.t) result`, with an all-fail outcome being `Error (Concurrent causes)` in input order and a single typed failure of the only branch being `Error (Fail e)`, so that the failure composes and nothing is wrapped twice. ^nfix-yrjy
3. As a kernel maintainer, I want a `.ocamlformat` at the root pinned to the ocamlformat version in the switch (`profile = default`, `margin = 90`), the tree formatted once, and `dune build @fmt` added to the gates in `AGENTS.md` and the delivery map, so that formatting is not a review topic. ^nfix-vzax
4. As a kernel maintainer, I want the `app` and `core` specs' affected stories (napp-kq3b, ncore-7vo9) reworded to the new shapes with a note that this spec supersedes them, so that the specs stay true. ^nfix-p822

## Implementation Decisions

- `serve` keeps `request_stop` semantics unchanged; only the query plumbing moves.
- `race`'s doc states the empty-list case: `Error (Concurrent [])`.
- If the switch has no ocamlformat, record that in this spec's status and stop on story 3 only; stories 1, 2, 4 do not depend on it.

## Testing Decisions

- `test/app`: a Service whose deps include the query, created before `serve`, answering a status inside `serve` — nfix-j678.
- `test/core`: race all-fail and single-branch-fail assertions on the Cause shape — nfix-yrjy.
- `dune build @fmt` green — nfix-vzax.

## Out of Scope

Anything else the review accepted: `Scope.run` owning its switch, child-fiber `Die`, the Door's exit policy, eio_posix for tests, ADR-0007, the absence of `@ local` annotations (a later OxCaml pass, with its own spec).

Verification: `nix develop -c dune build @install`, `nix develop -c dune test` (all ten suites, 179 tests, including `test/core`'s `nfix-yrjy race cause shape` and `test/app`'s `^nfix-j678` query-in-deps case) and `nix develop -c dune build @fmt` passed for the full tree.
Verification: ocamlformat 0.29.0 is in the switch; `.ocamlformat` pins `version = 0.29.0`, `profile = default`, `margin = 90`; the tree was formatted once, and doc comments that ocamlformat's comment check called ambiguous now end with a blank line so each attaches to its own value (they previously attached to both neighbours).
