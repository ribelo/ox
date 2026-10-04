---
status: ready
package: ox_lint (new, build-time only)
consumer: Ox and every consumer: the agents that write them (ADR-0010, row 86)
---

# `ox-lint`: our own rules, on the running compiler's own parser

## Problem Statement

The rules of row 66 and the conventions of row 86 need a decider, and both external options are weak here. **ast-grep has no OCaml support and will not get it**: the request was closed the day it was opened, by the maintainer, on popularity grounds ("TIOBE's top 50 programming language does not include OCaml yet"). **Semgrep's OCaml is Experimental by Semgrep's own definition**: pattern syntax limited to "Syntax, ellipsis operator, basic metavariable functionality", no resolution of `open`, no typed metavariables, no OCaml page in its documentation — and it cannot parse OxCaml mode syntax at all, which is why `caps-gate` falls back to a lexical identifier scan on four files of ox today (`lib/ox/schedule.mli`, `lib/sql/sqlite.ml`, `lib/sql/types.ml`, `lib/sql_dsl/ox_sql_dsl.ml`). A gate whose strongest rules degrade to grep on exactly the files with the most interesting types is the wrong foundation for the rules that remain.

There is a third option already proven in this tree. [`evidence/census.ml`](../suspend-token-cost/evidence/census.ml) — **57 lines** on the pinned compiler's own `compiler-libs` — walked all 192 production files and 24.660 kloc of ox and emitted, per file, every named function (locals and aliases included), every call, every identifier reference, every module alias, the enclosing `open` contexts and exact spans; row 75's transitive fixed point was computed on its output. That is a linter engine, used to count. And it is the argument of ADR-0007 for `ppx_yojson_minimal`, verbatim: the tree it reads is by construction the tree this compiler parses, so no AST port exists to rot, and OxCaml syntax is free.

## Solution

`ox_lint`: one executable over `compiler-libs`, two tiers — **Parsetree** for syntactic rules (most of them), **Typedtree read from the `.cmt` files dune already produces** (113 of them in `_build` today, `Cmt_format` is in `compiler-libs`) for the rules that need types. Rules live in one table with their fixture and their documentation page, as `caps.yaml` does. It is a build-time tool, in no package's runtime dependencies.

## User Stories

1. As a maintainer, I want `ox-lint [--rules R]... PATH...` on `compiler-libs`, printing one line per finding (file:line, rule id, message, the replacement to use) and exiting non-zero on any, so that `scripts/ox-check` (row 86) has a decider that reads the same syntax the compiler reads, including modes. ^nlint-jm8g
2. As a maintainer, I want the Parsetree tier to decide the rules Semgrep cannot express — `try ... with _ ->` or a handler binding the cancellation **whose body does not re-raise it first** (a statement-order condition, Trio's `ASYNC103`/`ASYNC104` shape); a suspending call inside a `Fun.protect ~finally` or `on_release` body (clippy's `await_holding_lock` shape); raw `Eio` concurrency, `Stdlib.Mutex`/`Condition`/`Semaphore`, `Obj.magic*`, a `deadline` written as `race` against a sleep, an `exception` declared in an `.mli` — **with `open` and module aliases resolved**, which is the single thing Semgrep's OCaml tier admits it cannot do. ^nlint-rv8u
3. As a maintainer, I want the Typedtree tier to decide what no syntactic tool can: whether a discarded expression (`ignore`, `let _ =`) really has type `result`; whether a handler binds exactly `Eio.Cancel.Cancelled` by path rather than by name; whether a call inside a protected body is really one of the suspending operations after aliases are resolved; and the transitive suspension closure row 71 needs, so that those rules have no name-matching false negatives. ^nlint-hxar
4. As a maintainer, I want the doc-comment rules decided here too — every `val` in `lib/**/*.mli` states its cancellation, suspension and finalizer behaviour, and its cancel safety where it applies (row 86 stories 6 and 9) — since `compiler-libs` gives the docstring attached to each `val` and its span, which no external linter can reach. ^nlint-yf56
5. As a maintainer, I want each rule to carry its id, its message naming the replacement, its violating and clean fixture, and its `docs/rules/` page, with `ox-lint --self-check` failing when any of the four is missing, so that row 66 story 12's triangle holds for our own rules by construction. ^nlint-emql
6. As a maintainer, I want every rule to state its decidable form and its accepted false negatives in its page — "does not re-raise", never "is unsafe", as detekt and clippy both do — so that a pass is not read as proof (row 86 story 4). ^nlint-9ftb
7. As a maintainer, I want `ox-lint` installed beside the caps gate and run by consumers against the version of ox they build with, as `share/ox_caps/caps-gate` already is, so that one tool decides every registered rule in every repository. `--repo-gate` discovers the repository; `--caps-gate` remains its compatible alias, without a capability-only rule filter. `--rules` still narrows selection, including the Dune mint-dependency check. The summary states selected, active and dormant rule counts, findings across those rules and undecided/excluded evidence counts; documented applicability (including deliberate raw-concurrency dormancy) is unchanged. ^nlint-r01u
8. As a maintainer, I want a parse failure to be a **gate failure naming the file**, never a silent skip, so that the degradation mode `caps-gate` had to work around cannot reappear. ^nlint-2nwm
9. As a maintainer, I want the scope decision recorded: `ox-lint` owns the **new** rules (row 66 stories 3–7 and 9–13, row 86 stories 6 and 9) from the start, while `caps-gate`'s 17 `ox-caps-*` rules stay on Semgrep until `ox-lint` has proven itself on them, and the migration is then its own row — because the caps gate works, is fixture-tested, and is a security boundary. ^nlint-4sct

## Implementation Decisions

The parser is `Parse.implementation`/`interface` through `compiler-libs`, as `evidence/census.ml` and `lib/ppx_yojson_minimal` already do (ADR-0007 admits `ocaml-compiler-libs` as a build-time dependency for exactly this reason; this row extends that admission to `ox_lint` and nothing else). The traversal is `Ast_iterator` with the `open` stack and alias map the census tool already builds. The Typedtree tier reads `.cmt` files with `Cmt_format` and is **optional per rule**: a rule that needs types is skipped with a named warning when the `.cmt` is absent, and `--require-typed` makes that a failure for the gate run.

Two risks, recorded: `compiler-libs` has no stability promise across compiler versions, which is the same exposure `ppx_yojson_minimal` already carries and is bounded by ox pinning one compiler exactly (ADR-0005); and reading `.cmt` on 5.4.0+ox was unverified until the spike below settled it.

What this cannot do, and what therefore stays elsewhere: timing (row 85's simulation), "this handler cannot raise" (undecidable, hence the "does not re-raise" form), and anything about a consumer's runtime configuration (row 75 found Leash's logging conflict is real in the type and absent at its configured level — a linter sees the first, not the second).

## Testing Decisions

One violating and one clean fixture per rule under `test/lint/`, in the shape of `test/caps/gate/`: the set of rule ids that must fire on the violating tree is pinned, a `nolint`-style comment must not silence anything, and the clean tree must pass. The five existing catch-all sites and 33 `Fun.protect` sites in `lib/` are the first real corpus: each is fixed or allow-listed with a reason in the same row that enables its rule.

## Out of Scope

Replacing the caps gate (story 9); formatting (`ocamlformat` owns it); type-driven whole-program analysis beyond the suspension closure.

## Spike result (2026-10-04): the typed tier is feasible, with conditions

Two workers settled story ^nlint-hxar on the pinned compiler; evidence and reproduction commands in [spike/REPORT.md](spike/REPORT.md) and [spike/interfaces/REPORT.md](spike/interfaces/REPORT.md), prototypes beside them.

**What works.** All **113** library `.cmt` files read as `Implementation` and traverse — zero failures, 53,238 expressions visited. The decisive rule runs end to end: of **40** `ignore`/`let _ =` discard candidates in `lib/`, **8** are genuinely `result`-typed — `http/ws_client.ml:426`, `otel/ox_otel.ml:426` and `:455`, `process/child.ml:134`, `sql/pool.ml:28`, `:57`, `:73`, `:105` — against the 39 sites a name-matching count had reported. Classification expands manifest aliases with `Ctype.expand_head` and compares type paths with `Path.same` against the canonical `result` looked up in the **initial** environment, so a local module named `Stdlib` cannot redefine what "really `result`" means; a local function named `ignore` is not mistaken for `Stdlib.ignore`; `@@` and `|>` forms elaborate to the real call and are caught. Interfaces: **97/97** `.cmti`, **1,301/1,301** `val` declarations with their types, spans and attached docs, and all **488** attached-doc sets matching the source — so story ^nlint-yf56 needs no second mechanism. OxCaml modes are inspectable in both the source and the artifact for all six mode-carrying files tested, including the four Semgrep cannot parse. Warm run over the whole typed corpus: **0.44 s** (0.76 s including `nix develop`).

**Conditions the implementation must meet, each from a measured failure.**

- **Environment reconstruction is not optional.** The stored environments are summaries: each annotation needs `Envaux.env_of_only_summary ~allow_missing_modules:false`, cache resets, and its visible and hidden load paths initialised. Dune records the remapped `/workspace_root` as `cmt_builddir`, which does not exist, so relative includes must be rebased onto the real `_build/default` — without this the typed tier does not work at all.
- **Inventory the expected modules; never glob what exists.** `lib/ppx_yojson_minimal/main.ml` is a native-only executable whose Dune rule omits `-bin-annot`, so it has no `.cmt` after `@install` while its interface annotation exists. A gate that globs would silently skip it. The gate declares the modules it must cover and fails when an annotation is missing or stale (story ^nlint-2nwm).
- **Exception identity needs the origin, not the UID.** Same-unit rebinding (`exception Stopped = Cancelled`) is matched through origin metadata, and UID equality alone is insufficient. Cross-unit rebinding is **unproven**; the rule states that limit.
- **Documented limits.** A node whose inferred type is still a variable is not established to be `result` and is not reported; there is no interprocedural reasoning; value aliases are not followed. Inferred parameter modes can retain bounds rather than constants, so a mode-reading rule must say which it tests. And 813 of the 1,301 `val`s carry no attached doc today — that number is a rule-design decision for row 89, not automatically 813 violations.

**Consequence for this row:** it delivers the engine, the rule table and the first typed rule (discarded `result`, with those eight sites fixed or allow-listed). The concurrency rules of row 66 move to [row 88](../ox-lint-rules/01-ox-lint-rules.md) and the interface-documentation rules to [row 89](../ox-lint-docs/01-ox-lint-docs.md), so each lands on its own evidence.
