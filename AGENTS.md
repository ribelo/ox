# Repository Guidelines

Read `CONTEXT.md` (vocabulary), then `docs/why-next.md` (why this tree exists and how code is written here), then `docs/adr/`. The previous design is on the `v1` tag; its source is reference material for pure codecs and nothing else.

## Landing

You are the only agent working here. Uncommitted work is lost work: commit each verified slice to `eta-next` (the branch of this worktree) with a message that cites the consumer story ID that justified it. Push only when asked.

## The one rule

Nothing enters this tree without a consumer. A change is justified by a user story in a consumer's spec (`<consumer>/docs/issues/<slug>/01-<slug>.md`, to-spec format) and cites its story ID. When a change is Eta-internal with no consumer story — the Door's own shape, say — it gets a spec of the same format under `docs/issues/<slug>/01-<slug>.md`, and `docs/issues/README.md` is the delivery map. There are no tickets, no requirement prose, no status essays in this repository.

## How code is written

- Direct style on Eio. No `Effect.t`, no runtime, no interpreter. Switches and Eio values are passed explicitly.
- `('a, 'err) result` with polymorphic-variant errors; exceptions are defects; `Scope.run` classifies at boundaries.
- Deadlines use `timeout`; `race` selects the first success.
- Pure protocol code is copied from `v1` when pulled; anything that mentioned `Effect.t` is rewritten.
- Stdlib-first; dependencies per ADR-0005; OxCaml features wherever they earn a guarantee or speed.
- Every package: `lib/<name>/`, a `.mli` per module, tests under `test/<name>/` citing the story IDs they cover.

## Gates (before any commit)

```sh
nix develop -c dune build @install
nix develop -c dune test
nix develop -c dune build @fmt
```
