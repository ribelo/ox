---
status: completed
package: ox (flake, dune-project, ox_test), ADR-0005; Leash, Pie, inn, nema, grip (flakes)
consumer: Ox-internal (the toolchain every consumer builds with)
---

# Upstream Eio, not the oxcaml/eio snapshot

## Problem Statement

Ox and every consumer built against `oxcaml/eio` at `7de26f5`: the commit the OxCaml opam repository's `eio.1.3+ox` points at, on no branch of that fork, two small build patches on top of a 2025 Eio and 218 commits behind upstream Eio 1.6. Nobody chose it; the v1 OxCaml migration pinned what resolved and recorded no reason, and every consumer flake copied the pin. Upstream Eio 1.6 builds on 5.4.0+ox unchanged.

## Solution

Every build takes upstream Eio's own release. The shared switch pins `eio`, `eio_posix`, `eio_linux`, `eio_main` 1.6 to the upstream release tarball; Nix resolutions put an opam repository holding exactly those four packages (from ocaml/opam-repository) first; `dune-project` requires `eio >= 1.6` so `1.3+ox` can never be chosen.

## User Stories

1. As a maintainer, I want ox, its shared switch and its Nix packages to build against upstream Eio 1.6 and never against `oxcaml/eio`, so that the concurrency runtime under every service is the maintained one and nobody has to know a fork exists. ^neio-k3vq
2. As a maintainer, I want `Ox_test`'s fake process manager and the test fakes of Eio's provider interfaces to satisfy Eio 1.6 (`environment`, `getenv_opt`, `spawn_unix ?uid ?gid ?login_tty`, `setsockopt`/`getsockopt`), refusing what they do not support rather than ignoring it, so that the fakes stay honest. ^neio-p7m2
3. As a consumer, I want my flake to take the Eio repository from ox (`ox.legacyPackages.<system>.eioOpamRepository`) instead of carrying its own fork pin, so that there is one place that says which Eio is used. ^neio-w4hd
4. As a maintainer, I want ADR-0005 to say that "Eio" means upstream Eio's release, so that the next migration does not quietly pin a fork again. ^neio-c8tz

## Implementation Decisions

- Eio 1.4 made `Net.getaddrinfo` raise instead of returning `[]`; `Ox_http.Client` and `Ws_client` already convert `Eio.Io` to `` `Connect ``, so no change.
- Eio 1.4 prefers returning `Fiber.any`'s value over cancelling quickly; `Concurrent.race`/`race_first` are built on it, so the `@stress` properties were run.
- `eio_linux` 1.6 needs `uring >= 2.15`, available from opam.ocaml.org and the pinned opam-repository.

## Testing Decisions

- Before touching the shared switch: a scratch Dune workspace with upstream Eio 1.6, uring 2.15, ox and each consumer — ox `@install`, `@runtest` (27 suites, 669 cases) and `@stress`; every consumer's `@install` and tests.

## Out of Scope

p-doom and taumel (on `v1`, not ox consumers). Mode annotations in Eio.
