# Repository Guidelines

Read `CONTEXT.md` (vocabulary), then `docs/why-ox.md` (why this tree exists and how code is written here), then `docs/adr/`. The previous design is on the `v1` tag; its source is reference material for pure codecs and nothing else.

## Landing

Other agent sessions may work in this checkout at the same time. Uncommitted work is lost work: commit each verified slice to `master` (this checkout) with a message that cites the story IDs that justified it, staging only the paths you changed; never commit, revert or stash another session's changes. Before taking a delivery-map row number, re-read `docs/issues/README.md` from disk. Push only when asked.

## The one rule

Every change is justified by a user story in a spec, in to-spec format, and its commit cites the story ID. Ox is its own consumer: a spec lives in an application's repository (`<consumer>/docs/issues/<slug>/01-<slug>.md`) or in this one (`docs/issues/<slug>/01-<slug>.md`), and an Ox spec needs no outside application to ask for it. Two things enter on Ox's own authority: everything on Scala Ox's floor (ADR-0009, `docs/design/ox-floor.md`), and everything that makes wrong code fail to compile or fail the gate (ADR-0010). `docs/issues/README.md` is the delivery map. There is no requirement prose and there are no status essays outside the specs.

These instructions, the ADRs and the specs were written by agents and bind agents; the human writes none of them. When one of them is wrong, fix it here rather than obey it.

## How code is written

- Direct style on Eio. No `Effect.t`, no runtime, no interpreter. Switches and Eio values are passed explicitly.
- `('a, 'err) result` with polymorphic-variant errors; exceptions are defects; `Scope.run` classifies at boundaries.
- Deadlines use `timeout`; `race` selects the first success.
- Pure protocol code is copied from `v1` when a spec needs it; anything that mentioned `Effect.t` is rewritten.
- Stdlib-first; dependencies per ADR-0005; OxCaml features wherever they earn a guarantee or speed.
- Every package: `lib/<name>/`, a `.mli` per module, tests under `test/<name>/` citing the story IDs they cover.
- Dangerous calls go through `Ox_caps.Cap_*` and require a capability in the signature (`docs/caps.md`); `scripts/caps-gate` refuses the raw ones.

## Gates (before any commit)

```sh
nix develop -c dune build @install
nix develop -c dune test
nix develop -c dune build @fmt
nix develop -c scripts/caps-gate
```
