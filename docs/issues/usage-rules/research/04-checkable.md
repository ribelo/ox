# 04-checkable — rules a machine, or an agent, can verify

**Subject.** How to write rules for a code library such that a machine — or an AI agent — can
verify it followed them. Evidence gathered 2026-10-04; every URL below was fetched on that day.
**Nothing in any repository was modified**; the only artifacts written are this report and the
raw fetched pages kept in `notes/` beside it.

**Paths.** A path without a scheme is relative to the ox checkout root,
`/home/ribelo/projects/ribelo/ocaml/ox`. Local facts come from reading that tree; upstream facts
come from the URLs given. Where a statement is my inference rather than a source's, it is marked
**(inference)**. Where a source's rule is clear but its rationale is not, that is said explicitly.

---

## 1. Findings that apply to ox

### F1. `[@@alert]`: a use-site diagnostic the compiler can be told to make fatal

- **The rule.** Mark a declaration with a named alert; every *reference* to it is reported, and the
  same name doubles as the switch that promotes those reports to errors.
- **Source.** Official docs: OCaml manual, "21 Alerts", <https://ocaml.org/manual/5.4/alerts.html>
  (introduced in 4.08). Verbatim: *"The identifier is used to control which alerts are enabled, and
  which ones are turned into fatal errors."* and, in §21.2, *"Controlling which alerts are enabled
  and whether they are turned into fatal errors is done either through the compiler's command-line
  option `-alert <spec>` or locally in the code through the `alert` or `ocaml.alert` attribute"*,
  with the spec item *"@id equivalent to ++id+id (enables id and turns it into a fatal-error)"*.
  The manual states the intended use: *"Those alerts can be used for instance to report usage of
  unsafe features, or of features which are only available on some platforms, etc."*
- **Real use in a standard library** (source code): `stdlib/domain.mli` opens with
  `[@@@alert unstable "The Domain interface may change in incompatible ways in the future."]`
  (<https://raw.githubusercontent.com/ocaml/ocaml/5.4/stdlib/domain.mli>); `stdlib/hashtbl.mli`
  carries `[@@@alert unsynchronized_access "Unsynchronized accesses to hash tables are a programming
  error."]` wrapped in `[@@@warning "-53"]` / `[@@@warning "+53"]`
  (<https://raw.githubusercontent.com/ocaml/ocaml/5.4/stdlib/hashtbl.mli>); `stdlib/stdlib.mli`
  turns the same names on and off around re-exports (`[@@alert "-unstable"]` / `[@@alert unstable ...]`,
  lines 1374–1382).
- **The defaults** (compiler source, <https://raw.githubusercontent.com/ocaml/ocaml/5.4/utils/warnings.ml>):
  `let default_disabled_alerts = [ "unstable"; "unsynchronized_access" ]` and the initial state
  `alert_errors = (Misc.Stdlib.String.Set.empty, true); (* all soft *)`. So a *custom* alert name is
  enabled and **soft** unless something makes it fatal. The stdlib's two names are off by default.
- **What it prevents.** Using a function whose misuse is a whole bug class without an explicit,
  greppable decision at the use site — the exact shape of ox's "dangerous calls go through
  `Ox_caps.Cap_*`" rule, but checked by the compiler instead of by a scanner.
- **How it is enforced there.** A compiler diagnostic at each reference; fatal when the alert is
  named with `@` (or `++`) via `-alert`/the attribute.
- **State in ox.** ox already declares alerts: `lib/caps/door/ox_caps_door.mli:36`
  `[@@alert mint "Only Ox_app and Ox_test mint a powerbox (docs/caps.md)."]`, plus alert blocks in
  `lib/caps/cap_sys.mli` and `lib/caps/cap_unix.mli`; `docs/caps.md` says the door's constructor is
  *"marked with a `mint` alert"*. No dune file in the tree passes `-alert` (grep over `dune`/`dune-project`
  and the whole tree, excluding `_build`). **(inference)** The `mint` alert is therefore soft today:
  it is the documentation, not the enforcement; the Semgrep/lexical gate is the enforcement.
- **Limit.** An alert can only be attached to *declarations you control*. You cannot alert
  `Eio.Fiber.fork` or `Stdlib.Mutex.lock`; those stay a scanner's job (this is what row 66 of
  `docs/issues/README.md` is for).

### F2. ox's build already fails on any warning — but warnings are not alerts

- **The rule.** Build with warnings as errors; every new warning is a build break for the agent
  that introduced it.
- **Source** (upstream source code): dune, `src/dune_rules/ocaml_flags.ml`
  (<https://raw.githubusercontent.com/ocaml/dune/main/src/dune_rules/ocaml_flags.ml>): the dev
  profile emits the computed warning set plus `"-strict-sequence"` and `"-strict-formats"`, and
  `(if dune_version >= (3, 21) then [ "-warn-error"; "+a" ] else [])`.
- **ox**: `dune-project` says `(lang dune 3.21)`, so `dune build`/`dune test` in the dev profile
  already turns every warning into an error. **(inference)** This is the cheapest enforcement ox has
  and it costs nothing new; it does **not** cover alerts, which are governed by `-alert` (F1). I
  did not find a source that says `-warn-error` also promotes alerts — see §4.

### F3. Semgrep's OCaml support is Experimental, and that word has a documented meaning

- **Source** (official docs): <https://docs.semgrep.dev/supported-languages.md> puts OCaml inside the
  accordion titled *"Click to view experimental languages for Semgrep Code."* The meaning is defined
  at <https://docs.semgrep.dev/references/language-maturity-levels.md>: support is *"These languages
  are supported by the Semgrep community. While Semgrep may develop rules or engine updates for
  these languages, they are not prioritized."* (community-supported level) and, for Experimental,
  *"There are limitations to this language's functionality. Reported issues are tracked and
  prioritized with best effort."* with a parse-rate bar of **90%+** (GA languages are 99%+) and the
  supported Semgrep syntax reduced to *"Syntax, ellipsis operator, basic metavariable functionality"*
  — i.e. no metavariable equality, no types/typing, no deep-expression operators.
- **Also**: there is no OCaml page in Semgrep's documentation. `https://docs.semgrep.dev/languages/ocaml`
  returns **HTTP 404**, while per-language pages exist for other languages: `docs/languages/python.mdx`
  in `semgrep/semgrep-docs` returns **HTTP 200** from
  <https://raw.githubusercontent.com/semgrep/semgrep-docs/main/docs/languages/python.mdx> (both status
  codes checked 2026-10-04).
- **What it prevents / costs.** Anything needing constant propagation through module opens, typed
  metavariables, or cross-file dataflow will silently not work. Concretely, an open bug:
  <https://github.com/semgrep/semgrep/issues/10354> (still open; filed 2024-07-05) — *"semgrep fails
  to parse module opens (like imports in Python) and limited scope opens and count them in its
  matches in OCaml"*, with the reporter marking it *"P0: blocking your adoption of Semgrep or
  workflow"*.
- **Maintainer evidence of a pattern-level gap** (issue/PR thread): the official rule
  `ocaml/lang/best-practice/hashtbl.yaml` still carries the comment
  *"TODO: add support for the syntax match ... with | exception ... -> ... First, we'd need to switch
  to tree-sitter-ocaml for parsing patterns."*
  (<https://raw.githubusercontent.com/semgrep/semgrep-rules/develop/ocaml/lang/best-practice/hashtbl.yaml>,
  touch-up in <https://github.com/semgrep/semgrep-rules/pull/3702> by mjambon, merged 2025-10).
  The same rule's message ends *"If your code uses the syntax ... it's fine and we apologize for not
  detecting it."* — the false negative is documented inside the rule.
- **The grammar side** (source code / archived repo): `semgrep/ocaml-tree-sitter-semgrep` is
  archived — its README says `**This repository is archived.**` — and the OCaml grammar now lives in
  the Semgrep repo under `libs/ocaml-tree-sitter-semgrep/lang/ocaml`, where `projects.txt` lists the
  19 real projects used for parsing statistics (`ocaml/ocaml`, `mirage/mirage`, `ocaml/dune`, …) and
  `extensions.txt` lists `.ml`. **Parse-rate numbers for OCaml are not published anywhere I found**
  (see §4).

### F4. Semgrep *reports* coverage rather than failing: `PartialParsing` and `paths.skipped`

- **Source** (official docs + the project's own output schema). The CLI reference documents
  `--verbose`: *"Show more details about what rules are running, which files failed to parse, etc."*
  (<https://docs.semgrep.dev/cli-reference.md>). The machine-readable output is specified in
  `semgrep_output_v1.jsonschema` (<https://raw.githubusercontent.com/semgrep/semgrep-interfaces/main/semgrep_output_v1.jsonschema>),
  whose header states *"this JSON output is part of the "API" of Semgrep"* and *"Any backward
  incompatible changes should require to upgrade the major version of Semgrep"*. There, the
  `PartialParsing` error variant is documented as *"list of skipped tokens. Since semgrep 0.97."*,
  and `paths` is `scanned_and_skipped` with a `skipped` array of `skipped_target` objects whose
  required fields are `path` and `reason`.
- **A maintainer correcting the common misreading** (PR by IagoAbal, merged 2023-04-25,
  <https://github.com/semgrep/semgrep/pull/7608>): *"When a file is partially analyzed e.g. due to an
  error while evaluating a metavariable-pattern operator in ONE rule, that does NOT mean that the
  entire file has been skipped (which is what CLI was reporting)!"*
- **What it prevents.** Treating "Semgrep exited 0" as "every line was checked". ox states the same
  observation in its own gate: *"Semgrep exits 1 for findings, but can exit 0 after only *partially*
  parsing an OxCaml source. Do not let its exit status decide whether coverage is complete."*
  (`lib/caps/caps-gate`, header comment).
- **Uncertain**: whether `--strict` covers parse errors. The CLI reference says only *"Return a
  nonzero exit code when WARN level errors are encountered. Fails early if invalid configuration
  files are present. Defaults to --no-strict."* — my reading is that this is about findings, not
  coverage; see §4.

### F5. How a project can handle files the scanner cannot parse: ox's own answer

This is the only project I found that turns the coverage problem into a *tested* mechanism, so it is
recorded here as the reference shape (source: code in a real project, `lib/caps/caps-gate`,
`lib/caps/caps.yaml`, `test/caps/gate/check.sh`).

- **Shape.** Run Semgrep with `--json`; parse the report; take the union of `paths.skipped` and
  every `errors[].path`/`errors[].spans[].file` that is in scope; for exactly those files run a
  token-level scan: comment/string/char masking that preserves byte offsets (`masked`), a regex per
  forbidden identifier, and a printed reason — `caps-gate: lexical scan lib/unparseable.ml (Semgrep
  PartialParsing)`.
- **The identifier list is derived, not maintained twice**: *"Every raw identifier is taken from
  positive Semgrep patterns, never a second hand-maintained list."* If the rule file yields no
  identifiers the gate exits 2 (*"the Semgrep rule file contains no raw identifiers"*).
- **Fail closed.** An error or skip entry without a usable path aborts with *"Semgrep ... has no
  usable path; cannot check coverage"* (exit 1), and the test suite asserts that this happens
  *"without a traceback"* — using a fake `semgrep` shell script that prints crafted JSON
  (`test/caps/gate/check.sh`, lines 56–78).
- **The escape hatch is central and reasoned, not per-line**: the gate passes `--disable-nosem`, and
  `check.sh` asserts that an inline `(* nosemgrep *)` *does not* silence a rule; the only allow-list
  is what the calling repository passes with `--allow`, each entry carrying its reason in that
  repository's `scripts/caps-gate`.
- **It is tested**: `test/caps/gate/skip-clean/lib/unparseable.ml` and
  `skip-violating/lib/unparseable.ml` are fixtures whose parse coverage is deliberately missing, with
  assertions on both outcomes (`exit 0` + the "lexical scan" line; `exit 1` + `forbidden identifier
  Unix.fork`).
- **What it prevents.** A rule that silently stops applying to the files the parser cannot read —
  which, per F3, is exactly the OCaml/OxCaml case.

### F6. A rule's own tests: annotations in the language, and metarules over the rule files

- **Source** (official docs): <https://docs.semgrep.dev/writing-rules/testing-rules.md> — *"`ruleid:
  <rule-id>` for protecting against false negatives `ok: <rule-id>` for protecting against false
  positives"*, with `todoruleid:`/`todook:` for known gaps, *"`--test` tells Semgrep to run tests in
  the specified directory"*, and *"Semgrep looks for tests based on the rule filename and the
  languages specified in the rule. In other words, `path/to/rule.yaml` searches for `path/to/rule.py`,
  `path/to/rule.js`, and similar"*. For OCaml this is live: `ocaml/lang/best-practice/hashtbl.ml`
  carries `(* ruleid:hashtbl-find-outside-try *)` and `(* ok *)` markers (seen in the pull-request
  diff of <https://github.com/semgrep/semgrep-rules/pull/3702>).
- **The contribution rule** (project's PR template, quoted in that PR body): *"The rule has **true
  positive** and **true negative** test cases in a file that matches the rule name."* plus a
  three-part message requirement (what the pattern is, why it is wrong, what to do instead).
- **CI** (<https://raw.githubusercontent.com/semgrep/semgrep-rules/develop/.github/workflows/semgrep-rules-test.yml>):
  `semgrep validate .` then `semgrep test .` over the whole rules repository.
- **Metarules** (<https://raw.githubusercontent.com/semgrep/semgrep-rules/develop/.github/workflows/semgrep-rule-lints.yaml>):
  the rules repository lints *its own rule files* with a list of rules run `--error` — `duplicate-id`,
  `duplicate-pattern`, `unsatisfiable`, `empty-message`, `missing-message-field`,
  `missing-language-field`, `metadata-confidence`/`likelihood`/`impact`/`subcategory` and four
  `*-incorrect-value` variants. **What it prevents:** a rule file that is broken, duplicated,
  unsatisfiable or unusable-as-documentation, i.e. the failure mode of a rule set that grows by
  agent edits.
- **Semgrep applies this to itself** (project source): <https://raw.githubusercontent.com/semgrep/semgrep/develop/semgrep.yml>
  notes *"Put semgrep-specific rules here. Put general OCaml or Python rules in the semgrep-rules
  repository under ocaml/ or python/."*, and the repo's own OCaml rules were adopted in
  <https://github.com/semgrep/semgrep/pull/1838> ("Use the new ocamllint semgrep rules and fix
  warnings", merged 2020-10-15, body: *"Dogfood! test plan: make test / make check"*).
- **The official OCaml pack** (source): 24 rule files under `ocaml/lang/` in `semgrep-rules`,
  including `ocaml/lang/best-practice/mutex.yaml` (`mutex-lock-exn`: *"Raw `Mutex.lock`/`Mutex.unlock`
  is not exception-safe..."*, added by <https://github.com/semgrep/semgrep-rules/pull/3801>),
  `hashtbl-find-outside-try`, `list-find-outside-try`, `bad-reraise`,
  `physical-equal`, `useless-if`, `ocamllint-marshal`, `ocamllint-tempfile`,
  `ocamllint-filenameconcat`, `ocamllint-exec`, `ocamllint-hashtable-dos`. Several ids still carry
  the `ocamllint-` prefix, but **I did not verify** where the standalone "ocamllint" Semgrep pack is
  published today (§4).

### F7. Compile-fail testing: three shapes, and the rule that the *message* is asserted

- **(a) ox's own harness** (code in a real project, `test/modes/compile_fail/check.sh`): a dune rule
  attached to `runtest` passes `%{ocamlc}` and an include path to a shell script; the script compiles
  a positive control (`control.ml` must compile), then requires each bad file to fail, and then
  greps the compiler output for the *expected reason*: `grep -q 'random:Random.State.t' "$tmp/out"`,
  failing with *"refused for an unrelated reason"* otherwise. The dune stanza is a plain
  `(rule (alias runtest) ...)` with `(glob_files compile_fail/*.ml)` as deps
  (`test/modes/dune`).
- **(b) The OCaml compiler's testsuite convention** (upstream docs,
  <https://raw.githubusercontent.com/ocaml/ocaml/trunk/testsuite/HACKING.adoc>): file-based tests
  compare a produced `.result` against a checked-in `.reference` (*"The tests succeeds if the
  .result and .reference files are identical."*), and expect-style tests use *"inline `[%%expect
  {|...|}]` blocks that contain the expected output for the toplevel phrases before them"*; the doc's
  own recommendation is *"expect-style tests are typically easier to read and maintain; we recommend
  using then whenever the feature that you want to test can be observed from the bytecode
  toplevel."* Failed expectations are updated by *"promotion"*, not by hand. The driver
  (`ocamltest`) is documented at <https://raw.githubusercontent.com/ocaml/ocaml/trunk/ocamltest/OCAMLTEST.adoc>.
- **(c) The lint-snapshot shape, for comparison** (a real project, Rust's Clippy,
  <https://raw.githubusercontent.com/rust-lang/rust-clippy/master/book/src/development/adding_lints.md>):
  *"Clippy uses UI tests for testing. UI tests check that the output of Clippy is exactly as
  expected. Each test is just a plain Rust file that contains the code we want to check. The output
  of Clippy is compared against a `.stderr` file."*, regenerated with `TESTNAME=... cargo uibless`.
  One snapshot file per rule, in the rule's own test file.
- **What (a)–(c) prevent:** a negative test that passes because the program broke for an unrelated
  reason (a syntax error, a missing include). Asserting *a fragment of the diagnostic* is the cheap
  version; asserting the whole output is the version you can promote.

### F8. Cram tests and `dune promote`: pinning a command-line tool's exact output

- **Source** (upstream docs, <https://raw.githubusercontent.com/ocaml/dune/main/doc/reference/cram.rst>):
  *"Cram tests are integrations tests that describe a shell session. These tests contain commands
  and expected outputs. When executed, the commands are executed and the actual output is compared
  to the expected output."*; *"When a Cram test is executed, the commands it contains are executed,
  and a corrected file is created where the command outputs are inserted after each command. This
  corrected file is then offered for promotion by Dune."*; *"All Cram tests are attached to the
  /reference/aliases/runtest alias. So `dune runtest` will run all Cram tests."* Stanza reference:
  <https://raw.githubusercontent.com/ocaml/dune/main/doc/reference/dune/cram.rst> (`(cram (deps ...))`,
  `(applies_to ...)`).
- **A real linter that does this** (code in a real project): zanuda pins its own diagnostics in
  `tests/typed/ExcTry.t/run.t` — the whole expected output is three lines, e.g.
  `Alert zanuda-linter: Antipattern: error swallowing`
  (<https://raw.githubusercontent.com/Kakadu/zanuda/master/tests/typed/ExcTry.t/run.t>). ox's
  `test/caps/gate/check.sh` asserts the same class of thing with hand-written `grep -q` checks; a
  cram test would make that output a single promotable file (see A7).

### F9. A wide `try ... with _ ->` can be caught mechanically, and someone already wrote the rule

- **Source** (code in a real project): zanuda, `src/typed/Exc_try_with_wildcard.ml` — `lint_id =
  "exc_error_swallowing"`, `group = LINT.Suspicious`, `level = LINT.Deny`, an embedded
  `documentation` string (*"Catching all possible exceptions with wildcard considered as
  antipattern"*, linking Wikipedia's "Error hiding"), message `"Antipattern: error swallowing"`, and
  a match on `texp_try ... (case tpat_any ...)`. It is registered per-project
  (`Config.is_lint_enabled`) and covered by the cram test above.
- **What it prevents.** Exactly ox's known bug class: *"swallowed `Eio.Cancel.Cancelled` by a wide
  `try ... with _ ->`"*, which the spec
  `docs/issues/raw-concurrency-gate/01-raw-concurrency-gate.md` states as story 3 and counts in the
  tree today: *"`with _ ->` swallowing `Eio.Cancel.Cancelled` (5 in `lib/`)"*.
- **The catch (why it is not a dependency)**: zanuda's lints *"study Typedtree, so the **input** for
  linter should be a **fully compiled dune project**"*
  (<https://raw.githubusercontent.com/Kakadu/zanuda/master/README.md>) and its opam constraint is
  `ocaml {>= "4.14.2" & < "5.0.0" | >= "5.3.0" & < "5.4.0" | >= "5.5.0" & < "5.6.0"}`
  (<https://raw.githubusercontent.com/Kakadu/zanuda/master/zanuda.opam>) — 5.4.0+ox is out of range.
  Camelot, the same genre, says *"for OCaml compiler version >= 4.10.0 < 4.14.0 (temporarily)"* and
  *"This project is dependent on compiler-libs, an inherently unstable library that changes between
  OCaml installations."*
  (<https://raw.githubusercontent.com/upenn-cis1xx/camelot/master/README.md>). `ocamllint` is
  archived by its maintainer: *"We're archiving `ocamllint` as it's not used at Cryptosense anymore
  and we believe there are better and more flexible lint tools available than a standalone binary."*
  (<https://raw.githubusercontent.com/cryptosense/ocamllint/master/README.md>).

### F10. `ppx_forbid`: the ban-list as a compile error, with a config file and a reversion attribute

- **Source** (project docs + opam metadata): <https://raw.githubusercontent.com/atacama-dev/ppx_forbid/main/README.md>
  — *"A configurable OCaml PPX that raises **compile-time errors** when forbidden functions or
  modules are used."*; a per-project `.ppx_forbid` file with lines `module Obj "Obj is unsafe and
  breaks type safety"` / `function Unix.sleep "Use Eio.Time.sleep"`; per-directory configs searched
  upward from the source file; suppression with `[@allow_forbidden "reason"]`; the emitted error is
  `Error: Forbidden call: Unix.sleep is not allowed. Suggestion: Use Eio.Time.sleep`. Its opam
  description names ox's own use case: *"Useful for enforcing coding standards like 'use Eio instead
  of blocking Unix calls' or 'never use Obj.magic'."*
  (<https://raw.githubusercontent.com/ocaml/opam-repository/master/packages/ppx_forbid/ppx_forbid.0.1.0/opam>).
- **What it prevents.** The raw call, at compile time, with no scanner and no coverage question — the
  one thing Semgrep cannot guarantee for a language at Experimental tier.
- **Costs** (see §3): needs `ppxlib >= 0.28.0`, is GPL-3.0-or-later, is version 0.1.0 (2026) and,
  per ADR-0010, `ppxlib` built for OxCaml is the blocker ox already recorded. The *pattern*, not the
  package, is the transferable part — and ox already has a hand-written ppx in `lib/ppx_yojson_minimal`
  built on `ocaml-compiler-libs.common`, which is the same dependency a lint ppx needs.

### F11. A rule an agent can verify: what the evidence actually says

- **Instruction files are context, not enforcement** (vendor docs,
  <https://docs.claude.com/en/docs/claude-code/memory>): *"Claude treats them as context, not
  enforced configuration. To block an action regardless of what Claude decides, use a PreToolUse
  hook instead. The more specific and concise your instructions, the more consistently Claude
  follows them."* The same page indexes troubleshooting entries such as *"Claude isn't following my
  CLAUDE.md"* and *"Instructions seem lost after /compact"*.
- **Polarity matters more than curation** (peer-review-style paper, abstract only):
  *"Guardrails Beat Guidance: A Large-Scale Study of Rules, Skills, and Persistent Configuration for
  Coding Agents"* (Zhang et al., arXiv:2604.11088, v2 2026-05-28,
  <https://arxiv.org/abs/2604.11088>): *"every individually beneficial rule is a negative constraint
  ("do not refactor unrelated code"), while every individually harmful one is a positive directive
  ("follow code style")"*; *"Random rules improve a coding agent's task performance as much as
  expert-curated ones (both +13.8pp ...)"*; and the stated principle *"constrain what agents must not
  do, rather than prescribing what they should."*
- **Context files do not buy correctness** (paper, abstract): *"Evaluating AGENTS.md: Are
  Repository-Level Context Files Helpful for Coding Agents?"* (Gloaguen et al., arXiv:2602.11988v3,
  2026-09-29, <https://arxiv.org/abs/2602.11988>): *"providing context files does not generally
  improve task success rates, while increasing inference cost by over 20% on average"*, and —
  the important half — *"while instructions in the context files are well followed by coding agents,
  repository overviews, although popular and recommended by model providers, are not helpful."*
- **File structure is not the lever; session position is** (paper, abstract): *"Instruction
  Adherence in Coding Agent Configuration Files: A Factorial Study of Four File-Structure Variables"*
  (McMillan, arXiv:2605.10039, 2026-05-11, <https://arxiv.org/abs/2605.10039>): across 1,650 sessions,
  *"None of the four structural variables or three two-way interactions produces a detectable
  contrast after multiple-testing correction"*, while *"each additional function the agent generates
  is associated with approximately 5.6% lower odds of compliance per step (OR = 0.944)"*.
- **What context files actually contain** (paper, abstract): *"Agent READMEs: An Empirical Study of
  Context Files for Agentic Coding"* (2,303 files from 1,925 repositories, arXiv:2511.12884v2,
  <https://arxiv.org/abs/2511.12884>): *"developers prioritize functional context, such as test
  procedures (75.9%), implementation details (70.8%), and architecture (68.1%)"* while *"security
  (14.8%) and performance (14.5%) are rarely specified."*
- **The file-name convention itself** (project/standard site, <https://agents.md/>): *"A simple, open
  format for guiding coding agents, used by over 60k open-source projects."*; *"Think of AGENTS.md as
  a README for agents: a dedicated, predictable place to provide the context and instructions to
  help AI coding agents work on your project."*; *"We intentionally kept it separate to: Give agents
  a clear, predictable place for instructions. Keep READMEs concise and focused on human
  contributors."* (The 60k figure is the site's own claim, not independently verified.)
- **(inference)** For ox, taken together: a prose rule in `AGENTS.md` is a *hint* whose force decays
  through the session; the rules that hold are the ones with a negative form and a command that
  fails. This is why the recommendation list below prefers gates over paragraphs.
- **The absence I could not fill**: no study I found isolates *"rule with a mechanical check"* versus
  *"rule without one"* as the experimental variable (§4).

### F12. Executable documentation, and the aliases that already exist in dune

- **mdx** (project docs, <https://raw.githubusercontent.com/realworldocaml/mdx/main/README.md>):
  *"MDX allows to execute code blocks inside markdown and mli/mld documentation to help keeping them
  up to date."*, enabled with a `(using mdx <version>)` stanza in `dune-project` and `(mdx)` in a
  `dune` file. The project README shows `(using mdx 0.2)`; the stanza reference
  (<https://dune.readthedocs.io/en/stable/reference/dune/mdx.html>, HTTP 200 on 2026-10-04) documents
  `(using mdx 0.4)` and notes *"Version 0.2 of the stanza requires mdx 1.9.0. Version 0.4 of the
  stanza requires mdx 2.3.0."* **What it prevents:** a doc comment that shows an API usage which no
  longer compiles.
- **`@fmt` / `@check` / `@lint`** (upstream docs, raw sources in `ocaml/dune` `doc/reference/`):
  *"This alias is used by formatting rules: when it is built, code formatters will be executed (using
  promotion) ... `dune fmt` is a shortcut for `dune build @fmt --auto-promote`."*
  (`aliases/fmt.rst`); *"`@check` ... will build `*.cmi`, `*.cmt`, and `*.cmti` files ... it will
  catch compilation errors without executing expensive operations such as linking executables"*
  (`aliases/check.rst`); *"This alias runs the linters configured by lint field ... If a PPX linter
  reports corrections, Dune displays them as diffs that can be applied with `dune promote`."*
  (`aliases/lint.rst`), with the field itself documented as *"`(lint <preprocess-spec>)`: Specifies
  how to lint source files when building the `@lint` alias. The default is `no_preprocessing`."*
  (`dune/library.rst`, line 107). ox already runs `dune build @fmt` as its fourth gate and has
  `.ocamlformat`/`.ocamlformat-ignore`.
- **`with-accepted-exit-codes`** (upstream docs,
  <https://raw.githubusercontent.com/ocaml/dune/main/doc/reference/actions/with-accepted-exit-codes.rst>):
  *"Specifies the list of expected exit codes for the programs executed in `<DSL>`"*, e.g.
  `(with-accepted-exit-codes (or 1 2) (run false))` — the dune-native way to express "this command is
  *supposed* to fail with 1".

---

## 2. Things ox should adopt, ranked

Ranked by (value to the stated goal) ÷ (cost), and written to *not* duplicate row 66 of
`docs/issues/README.md` ("no raw Eio concurrency or Stdlib mutex; catch-all, `Fun.protect`,
discarded result, public exception, `Obj.magic*` rules"), which is specified and `[ ]` (not
delivered) as of today. `lib/caps/caps.yaml` currently holds 17 rules, all `ox-caps-*`.

### A1. Make ox's existing alerts fatal in the directories that must not use them, and test that

- **Shape.** Top-level `dune`: `(env (_ (flags (:standard -alert @mint))))`; then
  `(env (_ (flags (:standard -alert -mint))))` in `lib/caps/dune`, `lib/app/dune`, `lib/test/dune`
  and the `bin` entry directories — the same allow-list `scripts/caps-gate` already passes with
  `--allow`, each entry with its reason. Add one compile-fail fixture (A2's harness) that names
  `Ox_caps_door.powerbox` from a library file and asserts both the failure and the alert text.
- **Why.** The `mint` alert already exists (`lib/caps/door/ox_caps_door.mli:36`) and is documented in
  `docs/caps.md`, but nothing makes it fatal (F1). This adds a *third* independent surface — compiler,
  Semgrep, lexical fallback — to the rule with the smallest amount of new code in the tree.
- **Cost.** ~5 small dune edits plus one fixture. The real cost is the duplicated allow-list: the
  gate's `--allow` and the dune `env` can drift. Cheapest mitigation: A3's script asserts that the
  two lists agree. **Not covered:** third-party values such as `Eio.Fiber.fork` cannot be alerted
  (F1's limit) — those stay row 66's job.

### A2. Pin the compiler's *reason*, not only its exit status, and cover every "Refused" line of ADR-0010

- **Shape.** Turn `test/modes/compile_fail/check.sh` into a table-driven harness: a plain-text
  `cases` file of `<file> <expected stderr fragment>` rows, one positive control per family, and a
  loop. Then add one fixture per bullet in ADR-0010's *"Verified on 5.4.0+ox"* list — the ADR already
  names both the refused programs and their compiler reasons ("already been used as unique",
  "expected to be many", "would escape its scope", "io is yielding but is expected to be unyielding"),
  so each row is a transcription, not a research task.
- **Why.** The existing harness is the right shape (F7a) but covers one story (`nwake-8qx5`,
  jitter sources). ADR-0010 is the document every agent reads to know what "does not compile" means;
  today five of its refusals are prose, and prose decays (F11).
- **Cost.** A ~30-line rewrite plus ~15 tiny fixtures and their accepted twins. No new dependency.

### A3. Lint the gate's own rule set, and check the rule → fixture → doc triangle

- **Shape.** One script (the gate already does this parsing in Python under `python3 /dev/fd/3`, so
  factor that snippet out), run from `scripts/caps-gate`, failing on: duplicate rule ids; a rule with
  no `message` or an empty one; a rule without `languages: [ocaml]`; a positive `- pattern:` whose
  first token yields no identifier for the lexical fallback (which would silently disable the
  fallback for that rule); a rule id that does not appear in `test/caps/gate/violating/lib/raw.ml`;
  a rule id that does not appear in `docs/caps.md`; and a `--allow` entry in `scripts/caps-gate` with
  no reason comment. Mirror of F6's metarules.
- **Why.** `check.sh` already pins the *set* of rule ids that must fire on the violating fixture
  (`expected="ox-caps-chdir ox-caps-env ..."`), which is the strongest existing invariant — but the
  doc side and the fallback side of the triangle are unchecked.
- **Cost.** One script (roughly the size of the existing Python block) + a table in `docs/caps.md`.

### A4. Row 66's `ox-catch-all`: keep the rule syntactic, keep the exemption lexical, write the false negatives down

- **Shape.** `pattern: try ... with _ -> ...` in `caps.yaml`, in the subset the Experimental tier
  allows (F3) — the same shape the official pack already ships for a handler test
  (`try ... with Not_found -> ...` in `hashtbl.yaml`), plus the existing lexical fallback for files
  Semgrep only partially parses (F5). Story 3's exemption *"unless the arm re-raises
  `Eio.Cancel.Cancelled` first"* is a statement-order condition inside the handler body, which the
  experimental syntax tier cannot express (no metavariable equality, no typed metavariables, no deep
  expression operators); implement it as an explicit lexical allowance and state the accepted false
  negatives in the spec, exactly as the same spec already does for story 4: *"Rule 4 cannot see
  types; it matches names, and its false negatives are accepted."*
- **Why.** This is the highest-value rule in row 66 and the one ox has been bitten by; F9 shows the
  semantics are understood well enough that another project implemented the same rule.
- **Cost.** The five existing sites in `lib/` (per the spec) must be fixed or allowed; a violating
  and a clean fixture per rule are required by story 8; the lexical exemption is new code in
  `caps-gate` and needs its own fixture (`skip-*` shows how). Expect false positives from
  `| _ ->` match arms that are not handlers — the pattern should name `try` specifically.

### A5. One table: rule → what it forbids → the replacement → the fixture → the command that fails

- **Shape.** A section of `docs/caps.md` (and the same table in row 66's spec as it lands) with one
  row per rule; A3 makes its completeness a build failure rather than a discipline.
- **Why.** F11: test procedures are the most common content of agent context files (75.9%) and the
  Claude Code docs say specificity and concision are what adherence tracks. A rule whose *check* is
  named next to it is the only form an agent can run instead of remember.
- **Cost.** Writing the rows; the mechanical part is A3.

### A6. Rewrite `AGENTS.md`'s doctrine as negative constraints, each with the command that checks it

- **Shape.** Keep the file short. For each hazard: what not to do, the replacement, and the command
  (`nix develop -c scripts/caps-gate`, `nix develop -c dune test`). Move the reasoning to the ADRs
  (where it already lives) and delete prose rules that no gate or test can see.
- **Why.** F11: beneficial rules are negative constraints and harmful ones are positive directives
  (2604.11088); instructions are context, not enforcement (Claude Code docs); compliance decays within
  a session (2605.10039). ox has no CI (see §3), so the file *is* the enforcement surface's index.
- **Cost.** An edit to `AGENTS.md` and to the specs' prose. Risk: losing rationale — mitigate by
  linking the ADR per row instead of restating it.

### A7. (Optional.) Convert `test/caps/gate/check.sh` into a dune cram test

- **Shape.** `test/caps/gate/*.t/run.t` directories with the same commands; expected output becomes
  the pinned file, updated by `dune promote`.
- **Why.** F8: the assertions today are ~40 hand-written `grep -q` checks whose failure mode is a
  silently-passing branch; cram shows the real output as a diff.
- **Cost.** Rewriting 174 lines; the promotion habit is itself a risk (a wrong output can be accepted
  by `dune promote`), which is why the Semgrep convention keeps *both* directions annotated
  (`ruleid:` and `ok:`) rather than only a snapshot (F6). Ranked last for that reason.

---

## 3. Things that look relevant but do not apply

1. **`llms.txt` for ox.** The proposal is for *websites*: *"A proposal to standardise on using an
   /llms.txt file to provide information to help agents use a website"* (Jeremy Howard, published
   2024-09-03, modified 2026-08-10, <https://llmstxt.org/>). ox is a private checkout that the agent
   already reads from disk; a published index adds a second, drifting copy of files the agent can
   open. The pattern is real where docs live on a website — Semgrep's own docs pages open with
   *"Fetch the complete documentation index at: https://docs.semgrep.dev/llms.txt"* — but that is not
   ox's situation.
2. **zanuda, camelot, ocamllint as dependencies.** All three are compiler-libs tools bound to
   compiler versions: zanuda's opam excludes 5.4.x and its README requires a fully compiled dune
   project; camelot is restricted to OCaml < 4.14 and warns that compiler-libs is unstable; ocamllint
   is archived by its maintainer (F9). Copy the *rule* (F9), not the tool.
3. **`ppx_forbid` as a dependency.** The mechanism is exactly what ox wants (F10) but the package
   needs `ppxlib`, which ADR-0010 records as unavailable for OxCaml: *"every `ppxlib+ox` in
   `oxcaml/opam-repository` requires `ocaml < 5.3.0`"* (`docs/adr/0010-modes-type-ownership-and-lifetime.md`).
   It is also GPL-3.0-or-later and at 0.1.0. If a compile-time ban is wanted, ox's existing
   hand-written ppx (`lib/ppx_yojson_minimal`, built on `ocaml-compiler-libs.common`) is the local
   precedent to extend.
4. **`ast-grep` as a Semgrep alternative with better OCaml support.** There is none: the feature
   request <https://github.com/ast-grep/ast-grep/issues/521> was closed the same day it was opened
   (2023-07-19) by the maintainer with *"While supporting new language is easy, it does impose some
   installation overhead for our end users. Please pardon me. My concern would be the popularity of
   OCaml. TIOBE's top 50 programming language does not include OCaml yet."*
5. **CI-hosted enforcement (the shape semgrep-rules uses).** ox has no `.github/workflows` (the
   directory does not exist in this checkout); the gates are run by the agent, per `AGENTS.md`. So a
   copy of *"semgrep validate . / semgrep test ."* in CI has nowhere to live; the equivalent is
   making the gate script carry its own tests (F5) and its own rule lint (A3). This raises, not
   lowers, the value of A1–A5.
6. **Semgrep interfile/cross-file analysis for OCaml.** The support table advertises *"Cross-file
   (interfile) analysis"* for the GA languages; OCaml appears only in the experimental accordion
   with no features listed, and the maturity table's Experimental syntax line stops at *"Syntax,
   ellipsis operator, basic metavariable functionality"* (F3). I found no statement that OCaml
   supports it, so ox's intra-file, one-rule-per-raw-call design is the right assumption — but this
   is an argument from absence, not a documented negative (§4).
7. **mdx on ox's `.mli` docs.** mdx executes code blocks in markdown and `mli` docs (F12). ox's
   doc comments describe semantics and invariants rather than runnable examples, so it buys little
   today; it becomes worth it only if the specs start showing example call sites that must compile.

---

## 4. What I could not find out

1. **Whether `-warn-error +a` promotes alerts.** The manual documents `-alert` as the control for
   fatality and `utils/warnings.ml` keeps `alert_errors` in a separate state initialized to
   *"all soft"*; I found no sentence about the interaction with `-warn-error`. Do not assume A1 is
   redundant with dune's dev profile without testing it.
2. **Semgrep's measured parse rate on OCaml.** The maturity page gives the *bar* for Experimental
   (90%+) but no measured number, and I found no published OCaml parse-rate figure; `projects.txt`
   shows the corpus used to compute one, not its value.
3. **Whether Semgrep's `--strict` covers parse errors.** The CLI help says *"Return a nonzero exit
   code when WARN level errors are encountered"*; I could not confirm whether `PartialParsing` counts.
4. **Whether `ppxlib >= 0.28` builds on OxCaml 5.4.0+ox.** I did not test it (mission is
   read-only). ADR-0010's recorded failure is about `ppxlib+ox` packages in `oxcaml/opam-repository`,
   which is evidence about that repository, not proof about upstream ppxlib.
5. **Where the standalone "ocamllint" Semgrep rule pack is published today.** I verified the 2020
   adoption PR in Semgrep's own repository and the `ocamllint-` prefixes in the official pack, but not
   an independent, currently maintained pack; the playground link in issue #10354 points at a
   personal organisation I did not verify.
6. **odoc as executable documentation.** I found no evidence that odoc executes or type-checks code
   blocks (mdx is the tool that does); I did not open odoc's warning-as-error configuration either.
   Treat "odoc can be a rule's check" as unverified.
7. **dune's `lint` field in detail.** I verified only the alias page and the library-stanza line
   (`(lint <preprocess-spec>)`, default `no_preprocessing`); the referenced `lint-field` page was not
   among the files I could locate, so the exact preprocess-spec syntax and what a ppx must implement
   to run in lint mode are unverified.
8. **Any OCaml project that publishes a rule → mechanical-check table.** I found none. The closest
   real artifacts are the OCaml compiler testsuite's conventions, Clippy's one-snapshot-per-lint
   layout, and the semgrep-rules checklist — all cited in §1.
9. **Whether "rule + its mechanical check" beats "rule as prose" for agent adherence.** I found no
   study that isolates that variable. The evidence I do have is indirect: instructions are followed
   but do not improve outcomes (2602.11988), negative constraints beat positive directives
   (2604.11088), compliance decays within a session (2605.10039), and the vendor recommends hooks
   over instruction files for blocking (Claude Code docs).
10. **Whether the Semgrep OCaml parser handles OxCaml's syntax** (mode annotations and the rest).
    No upstream statement exists; the only evidence is ox's own gate comment that Semgrep *"can exit 0
    after only *partially* parsing an OxCaml source"*, which is ox's observation, and the two
    `unparseable.ml` fixtures that encode it.
11. **Papers were read as abstracts only**, and none of them studies OCaml, Eio or ox; the numbers
    quoted in §1 are the abstracts' own. The arXiv identifiers are dated 2026 within this
    environment.
12. **The `agents.md` adoption figure** ("over 60k open-source projects") is the site's claim; I did
    not verify it independently.

---

## Summary

The strongest available facts point one way: for a library whose code is written by agents, a rule is
only as good as the command that fails when it is broken.

- **Alerts are the cheapest compiler-level lever ox has left unused.** ox already writes
  `[@@alert mint ...]` on the door and documents it, but nothing makes it fatal; the OCaml manual
  gives the exact switch (`-alert @id`), the stdlib shows the pattern in use, and dune's dev profile
  already fails on every ordinary warning.
- **Semgrep's OCaml support is Experimental by Semgrep's own definition** (90%+ parse-rate bar, no
  typed metavariables, no module-open resolution, an open pattern-level gap for `exception` arms) —
  and ox's `caps-gate` is the most complete answer I found to the resulting problem: read the JSON's
  `errors`/`paths.skipped`, re-derive the identifiers from the rule file, rescan exactly the
  uncovered files, fail closed on anything without a usable path, and test both outcomes with
  fixtures. That machinery is the part worth generalising to the rules row 66 still owes.
- **Negative tests must assert the reason**, not just the failure: ox already does this for one
  story; ADR-0010 lists five more refusals in prose that should become fixtures.
- **Rules need their own tests and their own linting**: Semgrep's `ruleid:`/`ok:` annotation pair,
  its "true positive and true negative" PR rule, and its metarules over rule files are all directly
  transferable to `caps.yaml`, whose rule set today is checked for firing but not for shape or
  documentation.
- **Agent-facing prose is a hint, not a gate.** The evidence says beneficial rules are negative
  constraints, structure matters less than expected, and adherence decays through a session; the
  vendor's own documentation says instruction files are context and hooks are the enforcement. Every
  rule worth keeping should appear in `AGENTS.md` as "do not X — check: <command>".

Report: `/tmp/eio-hardening/04-checkable/REPORT.md`
