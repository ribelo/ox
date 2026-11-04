---
status: ready
package: ox
consumer: every consumer (Ox-internal; ADR-0010)
---

# Scope handles cannot escape their scope

## Problem Statement

A switch or scope stored in a record, returned from its body, or captured by a later fiber is used after it finished; Eio reports it at run time (`Invalid_argument` or the switch's cancellation). OxCaml's `local` mode can refuse all three at compile time.

## Solution

`Scope.run : ('e t @ local -> ('a, 'e) result) -> ...`, `supervised_error`'s body likewise, and every scope operation taking `'e t @ local`. Long-lived forking goes through an explicit `Spawner.t` (`spawner`).

## Path

`let*` cannot carry a `local` handle: OxCaml elaborates binding operators with `global` continuations ("The value s is local ... because it is used in a letop"), and a `let*` declared with a `local` continuation is rejected. An ordinary application `bind r (fun x -> ...) [@nontail]` with a `local` continuation typechecks and keeps every refusal (ADR-0010), so this row is built on `ppx-let` (row 69). Postponed on 2026-10-03 while that looked impossible; reopened the same night once the `bind` route was verified.

## User Stories

1. As a service author, I want `Scope.run` and `Scope.supervised_error` to pass the scope `@ local`, so that storing it, returning it or capturing it in a fork is a compile error. ^nlscope-5jmh
2. As a service author, I want `fork`, `fork_error`, `on_release` and `switch`-free equivalents to take the scope `@ local`, and `Scope.switch` removed or returning a `local` switch, so that the Eio switch cannot be extracted globally. ^nlscope-0ngi
3. As a service author, I want a fiber that must fork further to open its own nested `Scope.run` or receive a `Spawner.t`, so that nested forking stays structured. ^nlscope-b9or
4. As a kernel maintainer, I want compile-fail cases (store, return, capture in a fork) and controls written through `let%bind`, so that the refusals and the ergonomics are pinned together. ^nlscope-dodx
5. As a kernel maintainer, I want an OxCaml issue filed asking for `local`/`yielding` continuations in binding operators, with the two refused programs, so that the ppx can be retired if the compiler moves. ^nlscope-idqy

## Progress

2026-11-04, expand step: `Scope.supervised` passes the scope `local` (story 1 for the new entry); `fork`, `fork_daemon`, `fork_error`, `fork_error_daemon`, `on_release`, `switch` and `spawner` take `'e t @ local`, so they serve both kinds of scope (story 2, first half); `spawner` copies the two global fields into a fresh record (story 3); `test/core/local_scope` pins store, return and fork-capture refusals and a `let%bind` control, plus the `let*` refusal (story 4). A function value of type `'e t @ local -> ...` is not accepted where `'e t -> ...` is expected, so a consumer that passes one of these as a first-class value may need an eta-expansion. Open: the contract step (`supervised_error` and `Scope.run` pass the scope `local`, `Scope.switch` removed) after Leash (142 `supervised_error` and 142 `Scope.switch` sites), Pie (12 and 10) and nema (1) move; story 5 (an OxCaml issue) needs the owner's word because it is public.

## Implementation Decisions

The scope record keeps its switch in a `global_` field and is abstract, so only Ox reaches the switch. Verified (ADR-0010) with the abstract type: escape, return and nested capture are refused; correct use compiles through `bind ... [@nontail]`.

## Out of Scope

Changing Eio's `Switch.run`.
