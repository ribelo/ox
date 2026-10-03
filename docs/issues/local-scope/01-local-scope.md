---
status: postponed
package: ox
consumer: every consumer (Ox-internal; ADR-0010)
---

# Scope handles cannot escape their scope

## Problem Statement

A switch or scope stored in a record, returned from its body, or captured by a later fiber is used after it finished; Eio reports it at run time (`Invalid_argument` or the switch's cancellation). OxCaml's `local` mode can refuse all three at compile time.

## Solution

`Scope.run : ('e t @ local -> ('a, 'e) result) -> ...`, `supervised_error`'s body likewise, and every scope operation taking `'e t @ local`. Long-lived forking goes through an explicit `Spawner.t` (`spawner`).

## Status: postponed

Decided 2026-10-03: accepted and postponed, because a `local` handle cannot be used after a `let*` — OxCaml elaborates binding operators with `global` continuations ("The value s is local ... because it is used in a letop"), and a `let*` declared with a `local` continuation is rejected. Evidence found the same night: an ordinary application `bind r (fun x -> ...) [@nontail]` with a `local` continuation typechecks and keeps every refusal (ADR-0010). This row therefore waits for `ppx-let`, not for the compiler.

## User Stories

1. As a service author, I want `Scope.run` and `Scope.supervised_error` to pass the scope `@ local`, so that storing it, returning it or capturing it in a fork is a compile error. ^nlscope-5jmh
2. As a service author, I want `fork`, `fork_error`, `on_release` and `switch`-free equivalents to take the scope `@ local`, and `Scope.switch` removed or returning a `local` switch, so that the Eio switch cannot be extracted globally. ^nlscope-0ngi
3. As a service author, I want a fiber that must fork further to open its own nested `Scope.run` or receive a `Spawner.t`, so that nested forking stays structured. ^nlscope-b9or
4. As a kernel maintainer, I want compile-fail cases (store, return, capture in a fork) and controls written through `let%bind`, so that the refusals and the ergonomics are pinned together. ^nlscope-dodx
5. As a kernel maintainer, I want an OxCaml issue filed asking for `local`/`yielding` continuations in binding operators, with the two refused programs, so that the ppx can be retired if the compiler moves. ^nlscope-idqy

## Implementation Decisions

The scope record keeps its switch in a `global_` field and is abstract, so only Ox reaches the switch. Verified (ADR-0010) with the abstract type: escape, return and nested capture are refused; correct use compiles through `bind ... [@nontail]`.

## Out of Scope

Changing Eio's `Switch.run`.
