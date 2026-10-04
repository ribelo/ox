#!/usr/bin/env bash
# ^nlint-hxar ^nlint-emql ^nlint-2nwm: compiled boundaries and complete required coverage.
set -eEuo pipefail
lint="$(realpath "$1")"
scratch="$(mktemp -d)"
# Only the directory returned by mktemp may be removed; never a computed repository path.
[[ -n "$scratch" && -d "$scratch" && "$scratch" = /* ]] || exit 2
trap 'rm -rf -- "$scratch"' EXIT
trap 'printf "fixture assertion failed at line %s\n" "$LINENO" >&2; cat "$scratch/out" "$scratch/err" >&2' ERR
expect() {
  local expected="$1"; shift
  local got
  if "$lint" "$@" >"$scratch/out" 2>"$scratch/err"; then got=0; else got=$?; fi
  if [[ "$got" != "$expected" ]]; then
    printf 'expected rc=%s, got rc=%s: %s\n' "$expected" "$got" "$*" >&2
    cat "$scratch/out" "$scratch/err" >&2
    exit 1
  fi
}
compile() {
  local kind="$1"
  mkdir "$scratch/$kind"
  cp "$kind/discard.ml" "$scratch/$kind/discard.ml"
  chmod u+w "$scratch/$kind/discard.ml"
  (cd "$scratch/$kind" && ocamlc -bin-annot -c discard.ml)
}
compile violating
compile clean
compile comment
compile stale
expect 1 --rules ox-discarded-result "$scratch/violating/discard.ml"
[[ "$(wc -l < "$scratch/out")" = 7 ]]
for line in 6 9 14 15 16 19 28; do
  grep -q ":$line: ox-discarded-result: discarded result; match Ok/Error" "$scratch/out"
done
expect 0 --require-typed "$scratch/clean/discard.ml"
[[ ! -s "$scratch/out" && ! -s "$scratch/err" ]]
expect 1 "$scratch/comment/discard.ml"
[[ "$(wc -l < "$scratch/out")" = 1 ]]
mkdir "$scratch/missing"
cp missing/discard.ml "$scratch/missing/discard.ml"
expect 2 --require-typed "$scratch/missing/discard.ml"
grep -q 'discard.ml:1: ox-lint: missing typed annotation' "$scratch/err"
# Also fail without the explicit strict flag: selected typed rules never silently skip.
expect 2 "$scratch/missing/discard.ml"
printf '\nlet newer = 1\n' >> "$scratch/stale/discard.ml"
expect 2 "$scratch/stale/discard.ml"
grep -q 'discard.ml:1: ox-lint: stale typed annotation' "$scratch/err"
printf 'let broken = (\n' > "$scratch/broken.ml"
expect 2 "$scratch/broken.ml"
grep -q 'broken.ml:1: ox-lint:' "$scratch/err"
expect 2 --rules no-such-rule "$scratch/clean/discard.ml"
grep -q 'unknown rule no-such-rule' "$scratch/err"
expect 2
expect 0 --help
grep -q 'Example:' "$scratch/out"
expect 1 "$scratch/violating/discard.cmt"
cp "$scratch/violating/discard.cmt" "$scratch/clean/discard.cmt"
expect 2 "$scratch/clean/discard.ml"
grep -q 'annotation belongs to another source' "$scratch/err"
printf garbage > "$scratch/bad.cmt"
expect 2 "$scratch/bad.cmt"
grep -q 'bad.cmt:1: ox-lint:' "$scratch/err"
# A missing imported CMI must not degrade alias expansion into a pass.
mkdir "$scratch/dependency"
printf "type ('a, 'e) outcome = ('a, 'e) result\n" > "$scratch/dependency/dependency.ml"
printf "let drop () = ignore (Ok 1 : (int, string) Dependency.outcome)\n" > "$scratch/dependency/use.ml"
(cd "$scratch/dependency" && ocamlc -bin-annot -c dependency.ml && ocamlc -bin-annot -c use.ml)
# Retain it under a different basename, so compiler load paths cannot resolve it.
mv "$scratch/dependency/dependency.cmi" "$scratch/dependency/dependency.saved"
expect 2 "$scratch/dependency/use.ml"
grep -q 'use.ml:1: ox-lint:' "$scratch/err"
mv "$scratch/dependency/dependency.saved" "$scratch/dependency/dependency.cmi"
printf '\nlet newer = 1\n' >> "$scratch/dependency/dependency.ml"
(cd "$scratch/dependency" && ocamlc -bin-annot -c dependency.ml)
expect 2 "$scratch/dependency/use.ml"
grep -q 'stale typed annotation: imported CMI fingerprint changed for Dependency' "$scratch/err"
expect 0 --self-check
# ^nlintc-kdcl: exercise CLI resolution as well as direct typed deciders.
for name in catch-all suspending-finalizer stdlib-lock obj-magic race-deadline; do
  fixture="${name//-/_}"
  expect 1 --rules "ox-$name" "violating/$fixture.ml"
  expect 0 --rules "ox-$name" "clean/$fixture.ml"
done
expect 1 --rules ox-public-exception violating/public_exception.mli
expect 0 --rules ox-public-exception clean/public_exception.mli
# Dormant even when explicitly selected; direct tests above exercise the decider.
expect 0 --rules ox-raw-concurrency violating/raw_concurrency.ml
# Installed resource discovery must not borrow missing evidence from this checkout.
mkdir -p "$scratch/installed/docs/rules" "$scratch/installed/test/lint/clean" "$scratch/installed/test/lint/violating"
cp "$lint" "$scratch/installed/ox-lint"
cp ../../docs/rules/ox-*.md "$scratch/installed/docs/rules/"
cp clean/*.ml clean/*.mli "$scratch/installed/test/lint/clean/"
cp violating/*.ml violating/*.mli "$scratch/installed/test/lint/violating/"
# ^ncapslint-snhg: installed self-check must carry all capability evidence too.
mkdir -p "$scratch/installed/test/caps/rules/clean" "$scratch/installed/test/caps/rules/violating"
cp ../caps/rules/clean/*.ml "$scratch/installed/test/caps/rules/clean/"
cp ../caps/rules/violating/*.ml "$scratch/installed/test/caps/rules/violating/"
cp ../../docs/caps.md "$scratch/installed/docs/"
chmod u+w "$scratch/installed/docs/caps.md"
original_lint="$lint"
lint="$scratch/installed/ox-lint"
expect 0 --self-check
# ^ncapslint-snhg: extra/duplicate allowance rows cannot masquerade as policy.
printf '\n<!-- caps-allowances -->\n| `unexpected/path` | undeclared |\n<!-- /caps-allowances -->\n' >> "$scratch/installed/docs/caps.md"
expect 2 --self-check
grep -q 'unexpected documented entry' "$scratch/err"
cp ../../docs/caps.md "$scratch/installed/docs/caps.md"
printf '\n<!-- caps-allowances -->\n| `lib/caps` | The Cap_* wrappers and token identity boundary contain the raw calls. |\n<!-- /caps-allowances -->\n' >> "$scratch/installed/docs/caps.md"
expect 2 --self-check
grep -q 'duplicate documented entry' "$scratch/err"
cp ../../docs/caps.md "$scratch/installed/docs/caps.md"
mv "$scratch/installed/docs/rules/ox-discarded-result.md" "$scratch/installed/docs/rules/missing"
expect 2 --self-check
grep -q 'missing documentation' "$scratch/err"
mv "$scratch/installed/test" "$scratch/installed/test.saved"
expect 2 --self-check
grep -q 'missing violating fixture' "$scratch/err"
grep -q 'missing clean fixture' "$scratch/err"
lint="$original_lint"
# All required sources must be declared, including native-only tools and interfaces.
python3 - <<'PY'
from pathlib import Path
rows = [line.split() for line in Path('modules.txt').read_text().splitlines() if line and not line.startswith('#')]
root = Path('../..')
actual = {str(p.relative_to(root)) for p in (root / 'lib').rglob('*')
          if p.suffix in ('.ml', '.mli') and not p.name.endswith(('.pp.ml', '.pp.mli'))
          and not any(part.startswith('.') for part in p.relative_to(root).parts)}
expected = {source for source, annotation in rows}
assert actual == expected, ('update modules.txt and exact dune deps', actual - expected, expected - actual)
assert len(expected) == len(rows), 'duplicate declared source'
for source, annotation in rows:
    assert (root / annotation).is_file(), ('missing required annotation', source, annotation)
PY
args=()
while read -r source annotation; do
  [[ -z "$source" || "$source" = "#"* ]] && continue
  args+=("../../$source")
done < modules.txt
# ^nlintc-kdcl ^nlintc-ayjk: run every applied row-88 rule; caps stays independent.
expect 0 --require-typed --rules ox-discarded-result --rules ox-catch-all --rules ox-suspending-finalizer --rules ox-stdlib-lock --rules ox-public-exception --rules ox-obj-magic --rules ox-race-deadline "${args[@]}"
[[ ! -s "$scratch/out" && ! -s "$scratch/err" ]]
printf 'compiled boundaries, evidence failures, and %s declared sources: pass\n' "${#args[@]}"
