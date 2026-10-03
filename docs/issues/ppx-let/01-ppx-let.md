---
status: ready
package: ppx_ox_let (new), ox
consumer: every consumer (Ox-internal; ADR-0010)
---

# `let%bind` whose continuations can be `local` and `yielding`

## Problem Statement

OxCaml elaborates `let*` with a `global unyielding` continuation. A `local` scope handle (`local-scope`) or a `yielding` suspension token (`suspend-token`) cannot be used after a `let*`, and Ox programs are `let*` chains, so both are blocked by syntax, not by soundness. An ordinary application `bind r (fun x -> body) [@nontail]` with a `local once yielding` continuation typechecks and keeps every refusal (ADR-0010). Jane Street writes this with ppx_let, which is not installable on 5.4.0+ox.

## Solution

A small rewriter on `ocaml-compiler-libs` (the `ppx_yojson_minimal` approach, ADR-0007), expanding `let%bind x = e in body` to `Ox.Result.bind e (fun x -> body) [@nontail]` and `let%map` to `Ox.Result.map`, with `Ox.Result.bind : ('a, 'e) result -> ('a -> ('b, 'e) result) @ local once yielding -> ('b, 'e) result`.

## User Stories

1. As a service author, I want `let%bind` / `let%map` (and `and%bind` for pairs) expanding to explicit application with `[@nontail]`, so that a `local` or `yielding` value can be used after a bind. ^nlet-q3z3
2. As a service author, I want `Ox.Result.bind` and `map` with `@ local once yielding` continuations beside the existing `Result.Syntax`, so that plain code keeps working unchanged. ^nlet-q79e
3. As a kernel maintainer, I want the rewriter's output checked by expect tests and its errors located at the user's source, so that a failure points at the program, not the expansion. ^nlet-axvf
4. As a kernel maintainer, I want a compile test proving a `local` scope and a `yielding` token both survive `let%bind` and both refusals still fire after it, so that the purpose is pinned. ^nlet-4eh4
5. As a kernel maintainer, I want the OxCaml issue from `local-scope` story 5 referenced in the package description, so that the rewriter is retired if binding operators gain mode-polymorphic continuations. ^nlet-z584

## Implementation Decisions

Verified (ADR-0010): `b_scope`, `b_io` compile through explicit `bind ... [@nontail]`; store, fork-capture and unyielding use are refused after it. The rewriter is a build-time dependency only, like `ppx_yojson_minimal`.

## Out of Scope

Other monads; `match%bind`.
