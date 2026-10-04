#!/usr/bin/env bash
# ^nlint-hxar ^nlint-2nwm: deployed evidence, qualified source identity and build membership.
set -euo pipefail
engine=$(realpath "$1")
root=$(realpath "$2")
fixture=$(realpath "$(dirname "$0")/project")
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ox-lint-deployment.XXXXXX")
scratch=$(realpath "$scratch")
case "$scratch" in /*/ox-lint-deployment.*) ;; *) exit 1 ;; esac
# All mutable evidence is confined to this verified disposable directory.
inside_scratch() { [[ $(realpath -m "$1") == "$scratch/"* ]]; }
cleanup() { inside_scratch "$scratch/project" && rm -rf -- "$scratch"; }
trap cleanup EXIT

expect() {
  local expected=$1
  shift
  local rc=0
  "$@" >"$scratch/out" 2>"$scratch/err" || rc=$?
  if [[ $rc != "$expected" ]]; then
    printf 'expected rc=%s, got rc=%s: %s\n' "$expected" "$rc" "$*" >&2
    sed -n '1,80p' "$scratch/out" "$scratch/err" >&2
    exit 1
  fi
}
contains() {
  if ! awk -v text="$2" 'index($0, text) { found=1 } END { exit !found }' "$1"; then
    printf 'missing diagnostic: %s\n' "$2" >&2
    sed -n '1,80p' "$scratch/out" "$scratch/err" >&2
    exit 1
  fi
}
# Owning ox_test dependency grants its constructor, never Door or sibling access.
cp -R "$(dirname "$0")/mint" "$scratch/mint"
chmod -R u+w "$scratch/mint"
inside_scratch "$scratch/mint/dune.in"; inside_scratch "$scratch/mint/dune"
mv "$scratch/mint/dune.in" "$scratch/mint/dune"
expect 0 "$engine" --caps-gate --rules ox-caps-mint "$scratch/mint/allowed.ml"
[[ ! -s "$scratch/out" ]]
expect 1 "$engine" --caps-gate --rules ox-caps-mint "$scratch/mint/direct_door.ml"
contains "$scratch/out" 'ox-caps-mint:'
expect 1 "$engine" --caps-gate --rules ox-caps-mint "$scratch/mint/sibling.ml"
contains "$scratch/out" 'ox-caps-mint:'
cp -R "$fixture" "$scratch/project"
chmod -R u+w "$scratch/project"
for path in dune-project qualified/dune bin/dune private/dune consumer/dune test/dune; do
  inside_scratch "$scratch/project/$path.in"
  inside_scratch "$scratch/project/$path"
  mv "$scratch/project/$path.in" "$scratch/project/$path"
done
project="$scratch/project"
dune build --root "$project" @install @check
# A test executable and its helper/interface are decided, not silently skipped.
expect 1 "$engine" --require-typed --rules ox-discarded-result "$project/test/entry.ml"
contains "$scratch/out" 'entry.ml:2: ox-discarded-result:'
expect 0 "$engine" --caps-gate --require-typed "$project/test/entry.mli" "$project/test/helper.ml" "$project/test/helper.mli"
[[ ! -s "$scratch/out" ]]
contains "$scratch/err" '0 modules with typed rules undecided'
expect 0 "$engine" --caps-gate --require-typed "$project/test/orphan.ml"
contains "$scratch/out" 'not built (not in any Dune target)'
contains "$scratch/err" '0 modules with typed rules undecided'
# Default inventory distinguishes declared data, marked compiled fixtures and orphans.
(cd "$project"; expect 0 "$engine" --caps-gate --require-typed)
contains "$scratch/err" ' data-only files out of scope; 1 fixture files skipped'
[[ $(<"$scratch/err") != *'; 0 data-only files out of scope;'* ]]
contains "$scratch/out" 'orphan.ml:1: ox-lint: not built'
expect 1 "$engine" --caps-gate --require-typed "$project/test/marked.ml"
contains "$scratch/out" 'ox-caps-fork:'
expect 1 "$engine" --caps-gate "$project/test/data/raw.ml"
contains "$scratch/out" 'ox-caps-fork:'
# A dead marker fails an explicit scan, while comments cannot mark a file.
cp "$project/test/marked.ml" "$scratch/marked.saved"
printf '[@@@ox_lint.fixture "ox-caps-fork: dead fixture"]\nlet fork () = 0\n' > "$project/test/marked.ml"
dune build --root "$project" @check
expect 2 "$engine" --caps-gate --require-typed "$project/test/marked.ml"
contains "$scratch/err" 'dead fixture: declared rule produced no finding'
printf '(* [@@@ox_lint.fixture "ox-caps-fork: only a comment"] *)\nlet fork () = Unix.fork ()\n' > "$project/test/marked.ml"
dune build --root "$project" @check
(cd "$project"; expect 1 "$engine" --caps-gate --require-typed)
contains "$scratch/out" 'marked.ml:2: ox-caps-fork:'
contains "$scratch/err" '0 fixture files skipped'
inside_scratch "$scratch/marked.saved"; inside_scratch "$project/test/marked.ml"
mv "$scratch/marked.saved" "$project/test/marked.ml"
dune build --root "$project" @check
test_cmt="$project/_build/default/test/.entry.eobjs/byte/dune__exe__Entry.cmt"
[[ -f "$test_cmt" ]]
inside_scratch "$test_cmt"
mv "$test_cmt" "$scratch/test.cmt.saved"
expect 2 "$engine" --caps-gate --require-typed "$project/test/entry.ml"
contains "$scratch/err" 'missing typed annotation; run dune build @check'
contains "$scratch/err" '1 modules with typed rules undecided'
# No explicit paths: the conventional test tree belongs to the default gate scope.
(cd "$project"; expect 2 "$engine" --caps-gate --require-typed)
contains "$scratch/err" '1 modules with typed rules undecided'
# A successful workspace query alone cannot prove exclusion when rules are unavailable.
mkdir "$scratch/no-rules"
printf '%s\n' '#!/usr/bin/env bash' 'if [[ $1 == describe && $2 == rules ]]; then exit 1; fi' 'exec "$DUNE_REAL" "$@"' > "$scratch/no-rules/dune"
chmod +x "$scratch/no-rules/dune"
expect 2 env DUNE_REAL="$(command -v dune)" PATH="$scratch/no-rules:$PATH" "$engine" --caps-gate --require-typed "$project/test/entry.ml"
contains "$scratch/err" '1 modules with typed rules undecided'
mv "$scratch/test.cmt.saved" "$test_cmt"
# Dune exposes only public_cmi to build-tree consumers; private CMIs stay in byte.
private_objects="$project/_build/default/private/.deployment_private.objs"
[[ -f "$private_objects/byte/deployment_private__Hidden.cmi" ]]
[[ ! -e "$private_objects/public_cmi/deployment_private__Hidden.cmi" ]]
expect 0 "$engine" --caps-gate --require-typed "$project/consumer/consumer.ml" "$project/consumer/consumer.mli"
contains "$scratch/err" '0 modules with typed rules undecided'
build_private_cmi="$private_objects/byte/deployment_private__Hidden.cmi"
inside_scratch "$build_private_cmi"; inside_scratch "$build_private_cmi.saved"
mv "$build_private_cmi" "$build_private_cmi.saved"
expect 2 "$engine" --caps-gate --require-typed "$project/consumer/consumer.ml"
contains "$scratch/err" 'missing imported CMI Deployment_private__Hidden'
mv "$build_private_cmi.saved" "$build_private_cmi"
# Install for real, then compile a separate consumer against that prefix only.
private_prefix="$scratch/private-prefix"
dune install --root "$project" --prefix "$private_prefix" deployment_private
private_cmi="$private_prefix/lib/deployment_private/.private/deployment_private__Hidden.cmi"
[[ -f "$private_cmi" ]]
mkdir "$scratch/installed-consumer"
cp "$project/consumer/consumer.ml" "$project/consumer/consumer.mli" "$scratch/installed-consumer/"
cp "$project/consumer/dune" "$scratch/installed-consumer/dune"
printf '(lang dune 3.21)\n' > "$scratch/installed-consumer/dune-project"
export OCAMLPATH="$private_prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
dune build --root "$scratch/installed-consumer" @check
expect 0 "$engine" --caps-gate --require-typed "$scratch/installed-consumer/consumer.ml" "$scratch/installed-consumer/consumer.mli"
contains "$scratch/err" '0 modules with typed rules undecided'
# A found private CMI still has to match the recorded fingerprint.
inside_scratch "$private_cmi"; inside_scratch "$private_cmi.saved"
mv "$private_cmi" "$private_cmi.saved"
expect 2 "$engine" --caps-gate --require-typed "$scratch/installed-consumer/consumer.ml"
contains "$scratch/err" 'missing imported CMI Deployment_private__Hidden'
cp "$project/_build/default/qualified/.deployment_qualified.objs/byte/deployment_qualified__Other__Dictation.cmi" "$private_cmi"
expect 2 "$engine" --caps-gate --require-typed "$scratch/installed-consumer/consumer.ml"
contains "$scratch/err" 'imported CMI fingerprint changed'
mv "$private_cmi.saved" "$private_cmi"
objects="$project/_build/default/qualified/.deployment_qualified.objs/byte"
cmt="$objects/deployment_qualified__Assistant__Dictation.cmt"
cmti="$objects/deployment_qualified__Assistant__Dictation.cmti"
[[ -f "$cmt" && -f "$cmti" ]]
# The basename of the annotation is deliberately no longer a module name.
inside_scratch "$cmt"; inside_scratch "$objects/evidence.cmt"
mv "$cmt" "$objects/evidence.cmt"
expect 1 "$engine" --rules ox-discarded-result "$project/qualified/assistant/dictation.ml"
contains "$scratch/out" 'dictation.ml:2: ox-discarded-result:'
expect 0 "$engine" --require-typed --rules ox-discarded-result \
  "$project/qualified/assistant/dictation.mli" "$project/qualified/other/dictation.ml"
# Keep the renamed-evidence assertion above; Dune rule discovery may clean unknown targets.
mv "$objects/evidence.cmt" "$cmt"
expect 0 "$engine" --caps-gate --require-typed "$project/bin/skill_cli.mli"
contains "$scratch/out" 'not built (not in any Dune target)'
contains "$scratch/err" '0 modules with typed rules undecided'

executable_cmt="$project/_build/default/bin/.main.eobjs/byte/dune__exe__Main.cmt"
[[ -f "$executable_cmt" ]]
inside_scratch "$executable_cmt"; inside_scratch "$executable_cmt.saved"
mv "$executable_cmt" "$executable_cmt.saved"
expect 2 "$engine" --caps-gate --require-typed "$project/bin/main.ml"
contains "$scratch/err" 'missing typed annotation; run dune build @check'
contains "$scratch/err" '1 modules with typed rules undecided'
# No Dune/inventory must not silently turn a missing module into "not built".
expect 2 env PATH="$scratch/no-dune" "$engine" --caps-gate --require-typed "$project/bin/main.ml"
contains "$scratch/err" '1 modules with typed rules undecided'
dune build --root "$project" @check
expect 0 "$engine" --caps-gate --require-typed "$project/bin/main.ml"

# Imported CMI fingerprints still fail closed after the broader lookup.
imported="$objects/deployment_qualified__Assistant__Dictation.cmi"
inside_scratch "$imported"; inside_scratch "$imported.saved"
mv "$imported" "$imported.saved"
cp "$objects/deployment_qualified__Other__Dictation.cmi" "$imported"
expect 2 "$engine" --require-typed --rules ox-discarded-result "$project/qualified/assistant/dictation.ml"
contains "$scratch/err" 'imported CMI fingerprint changed'
inside_scratch "$imported.saved"; inside_scratch "$imported"
mv "$imported.saved" "$imported"

# Restoring a same-basename but wrong-source annotation is rejected, not accepted.
sibling="$project/qualified/assistant/dictation.cmt"
cp "$objects/deployment_qualified__Other__Dictation.cmt" "$sibling"
expect 2 "$engine" --require-typed --rules ox-discarded-result "$project/qualified/assistant/dictation.ml"
contains "$scratch/err" 'annotation belongs to another source'
inside_scratch "$sibling"; rm -- "$sibling"
printf '\n(* changed after the build *)\n' >> "$project/qualified/assistant/dictation.ml"
expect 2 "$engine" --require-typed --rules ox-discarded-result "$project/qualified/assistant/dictation.ml"
contains "$scratch/err" 'stale typed annotation'

# Every compiled marked fixture must still trip its named rule.
for source in "$root"/test/lint/violating/*.{ml,mli} "$root"/test/caps/rules/violating/*.ml; do
  [[ -f "$source" ]] || continue
  IFS= read -r first < "$source" || true
  if [[ "$first" == '[@@@ox_lint.fixture "'* ]]; then
    rule=${first#*\"}; rule=${rule%%:*}
    expect 1 "$engine" --require-typed --rules "$rule" "$source"
    contains "$scratch/out" "$rule:"
  fi
done

prefix="$scratch/prefix"
data="$prefix/share/ox_lint"
mkdir -p "$prefix/bin" "$data/docs" "$data/test/lint" "$data/test/caps" "$scratch/elsewhere"
cp "$engine" "$prefix/bin/ox-lint"
cp -R "$root/docs/rules" "$data/docs/"
cp "$root/docs/caps.md" "$data/docs/"
cp -R "$root/test/lint/clean" "$root/test/lint/violating" "$data/test/lint/"
cp -R "$root/test/caps/rules" "$data/test/caps/"
cd "$scratch/elsewhere"
# Compare automatic discovery with an explicit root. Other workers may be adding
# rules/pages concurrently; their missing evidence must not mask a lookup regression.
baseline_rc=0
"$engine" --self-check --root "$root" >"$scratch/baseline.out" 2>"$scratch/baseline.err" || baseline_rc=$?
[[ $baseline_rc == 0 || $baseline_rc == 2 ]]
if [[ $baseline_rc == 2 ]]; then
  printf 'deployment self-check preserves explicit-root failures (upstream evidence incomplete)\n' >&2
fi
resolved_self_check() {
  expect "$baseline_rc" "$@"
  cmp "$scratch/baseline.out" "$scratch/out"
  cmp "$scratch/baseline.err" "$scratch/err"
}
resolved_self_check "$prefix/bin/ox-lint" --self-check
resolved_self_check "$engine" --self-check
# Explicit roots override executable layout and must never silently fall back.
resolved_self_check "$engine" --self-check --root "$data"
mkdir "$scratch/empty"
expect 2 "$prefix/bin/ox-lint" --self-check --root "$scratch/empty"
contains "$scratch/err" 'missing documentation'
adjacent="$scratch/adjacent"
mkdir "$adjacent"
cp -R "$data/docs" "$data/test" "$adjacent/"
cp "$engine" "$adjacent/ox-lint"
page="$data/docs/rules/ox-discarded-result.md"
inside_scratch "$page"; inside_scratch "$page.missing"
mv "$page" "$page.missing"
cd "$root"
expect 2 "$prefix/bin/ox-lint" --self-check
contains "$scratch/err" 'ox-discarded-result: missing documentation'
resolved_self_check "$prefix/bin/ox-lint" --self-check --root "$root"
# Partial legacy adjacent installs must never borrow this valid checkout's evidence.
resolved_self_check "$adjacent/ox-lint" --self-check
inside_scratch "$adjacent/test"; inside_scratch "$adjacent/test.missing"
mv "$adjacent/test" "$adjacent/test.missing"
expect 2 "$adjacent/ox-lint" --self-check
contains "$scratch/err" 'missing violating fixture'
inside_scratch "$adjacent/test.missing"; inside_scratch "$adjacent/test"
mv "$adjacent/test.missing" "$adjacent/test"
inside_scratch "$adjacent/docs"; inside_scratch "$adjacent/docs.missing"
mv "$adjacent/docs" "$adjacent/docs.missing"
expect 2 "$adjacent/ox-lint" --self-check
contains "$scratch/err" 'missing documentation'
printf 'deployment: qualified identity, membership, freshness, prefix and root override: pass\n'
