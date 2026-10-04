# Capabilities: a function's type says what it may touch

Rows 48, 54 and 90 (^ncaps-xzx5 ^ncaps-uiq6 ^ncapslint-nf4t). A function touching ambient process resources declares its authority in argument types. No repository file is exempted.

Resource-bearing interface vals also follow the [documentation contract](<rules/interface-documentation.md>); its rules check the sentence against the implementation, and name undecided whatever evidence they cannot resolve (^nlintd-7r1a).

## Authority

Ox_caps.Cap has fifteen abstract-token object capabilities. Rows compose them, for example `< Cap.fork; Cap.exec; .. >`. Lookalike objects cannot manufacture tokens. Cap_unix, Cap_sys and Cap_stdlib explicitly annotate implementation arguments with their interface rows: wrappers are not privileged paths. Random-device reads also take fs_read; opening /dev/null for output takes fs_write; spawning takes fork, exec and fs_write for output redirection.

Eio's net, fs, process_mgr, clock and domain_mgr remain explicit Eio values. These capabilities complement Eio rather than replacing it. Narrow a powerbox to the smallest needed row. Typed checking follows genuine argument authority through records, tuples, options, variants, payloads, projections and aliases; callbacks may capture an outer argument. Globals and locally minted tokens are not argument authority.

```ocaml
let spawn ~caps:(_ : < Ox_caps.Cap.fork; .. >) () = Unix.fork ()
let caller ~caps () = Ox_caps.Cap_unix.fork ~caps ()
```

## Minting boundary

The Dune stanza owning a source must directly list `ox_caps.door` before that source can name Ox_caps_door or mint through its powerbox or Ox_app.with_powerbox. A direct `ox_test` dependency additionally authorizes only `Ox_test.powerbox ()`, the sanctioned test entry: mint once there and narrow the resulting row for each helper. This is not a general transitive grant; another stanza's dependency or a comment grants nothing. Module selectors and include_subdirs determine ownership.

The Door, tests and build tools follow this same structural rule. CLI-owning entries mint directly through `Ox_caps_door.powerbox ()`, avoiding Ox_app's runtime closure. Ox_app still mints once per process and passes capabilities in its Env. Tokens remain abstract; no mint alert suppression or path exception is needed.

## Gate and installation

The checkout [caps-gate](<../scripts/caps-gate>) execs the built engine with `--caps-gate --require-typed`.

```sh
nix develop -c dune build @install
nix develop -c scripts/caps-gate
```

ox_lint installs bin/caps-gate beside bin/ox-lint; its launcher execs the sibling with --caps-gate. ox_caps installs no launcher and does not depend on ox_lint. Consumers install the compiler-matched build tool. --allow, --rules, --self-check and --require-typed remain supported. Exit codes are 0 (clean), 1 (findings/missing required evidence), and 2 (usage/setup failure).

The shipped allow-list is empty. Both registries and the checkout launcher's absence of --allow entries are regression-tested. Explicit --allow patterns and their existing fixture remain available for a future deliberate policy change; no default entry exists today.

## Fixture scope

Explicit source or annotation arguments override Git ignores, project boundaries and data-only classification; directory discovery (including the data-dependency inventory) honors Git ignores, and missing named paths remain errors even if ignored.

The default gate discovers the entire Dune workspace, with no hardcoded source-root list, then inventories each source against declared compilation targets (including tests and benchmarks). A source consumed by a declared data dependency but compiled by no target is counted as data-only and is out of default scope; an orphan remains reported as not built. Compilation takes precedence over data dependencies. Literal file, `source_tree` and `glob_files` dependencies (including named dependencies and included Dune stanzas) are recognized; variable dependencies are not treated as proof of data-only scope.

Compiled negative evidence belongs to nested directories with their own `dune-project` (^ncapslint-2606). These are separate Dune projects in the same workspace: Dune still builds their libraries and fresh `.cmt`/`.cmti` artifacts, but default gate discovery stops at each nested project boundary. No source attribute or per-file exemption exists. Explicit source, annotation and directory arguments cross project boundaries. Exact-site source/typed regression tests fail if a fixture stops violating; installed self-check audits the source-only bundle structurally.

Repository `dune test` explicitly scans every declared compiled negative fixture and verifies its exact finding sites using fresh typed evidence. Expectations live in the test harness, not in source attributes. Installed `--self-check` audits the rule/replacement/fixture/page bundle structurally because installations ship source fixtures without compiler annotations. The raw-concurrency rule stays deliberately dormant until rows 61, 64 and 65 land.

`--inventory` emits one tab-separated `PATH`, `DECISION`, `REASON` record per inventoried path on stdout. Decisions are `decided`, `undecided`, or `excluded`; structural exclusions name `data-only`, `not-built`, `ignored`, `nested-project`, `directory-cycle` or `no-ocaml` (directory records ending `/` cover their subtree). Findings and diagnostics stay on stderr. Compiled generated inputs join directory scans and name their producing Dune rule or stanza; unresolved provenance is undecided, never an exclusion.

## Rules

The fifteen operation categories and [ox-caps-signature](<rules/ox-caps-signature.md>) share one typed definition: a resolved raw dangerous reference is legal exactly when an enclosing argument supplies its matching genuine capability. The signature rule also checks provenance at wrapper calls. Each category retains its rule/clean-fixture/violating-fixture triangle.

[ox-caps-mint](<rules/ox-caps-mint.md>) checks the owning constructor dependency. [ox-caps-forge](<rules/ox-caps-forge.md>) rejects Obj.magic; unchecked casts cannot establish token authority.

Stdlib lock construction and synchronous critical sections pass. [ox-stdlib-lock](<rules/ox-stdlib-lock.md>) rejects a known scheduler suspension while a Stdlib mutex or semaphore is held. Exceptions in module-type contracts or modules declared private by the owning Dune stanza are allowed; package-published exceptions are not. ox-raw-concurrency is dormant everywhere until rows 61, 64 and 65 provide replacements: whole-rule activation, not a file exemption.

## What the gate cannot see

Source resolution respects lexical binders, opens and aliases. A non-wildcard/non-unit parameter may carry authority, so its raw references defer to typed evidence. Source-only success does not prove signature correctness. Naked references and argumentless functions can be rejected without typed evidence.

Fresh annotations establish normalized compiler identity, genuine token identity and argument provenance. Opaque higher-order forwarding, dynamic loading, FFI behaviour and arbitrary whole-program call graphs remain outside analysis. Compiler-library read APIs explicitly require fs_read even without Ox_caps wrappers. Metadata calls are not all named raw-call targets. These are visibility limits, not permission to hide authority.

Grant discovery reads literal owning Dune stanzas/module selectors. It does not evaluate included/generated forms, variables or conditional dependency expressions; those do not grant minting. Missing/stale typed evidence is reported as undecided; --require-typed fails it.

## Former exemptions

- Wrappers: exact argument rows checked by the shared decision.
- Door and tests: direct constructor dependencies.
- Linter and ppx: capability-taking helpers and declared minting entry boundaries.
- SQL/TLS public exceptions: top-level declarations removed; functor contracts remain.
- SQLite C-state and IPC table locks: synchronous sections, not forbidden construction.
- Reserved future trusted-cast path: removed; future casts face the active rule.

No allow-list entry is needed for any of them.
