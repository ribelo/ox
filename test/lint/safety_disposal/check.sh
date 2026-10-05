#!/usr/bin/env bash
# ^safe-pufa ^safe-fr73 ^safe-y047: installed CLI is the policy/evidence seam.
set -euo pipefail
bin="$1"
expect () {
  local expected="$1"; shift
  set +e
  "$bin" "$@" >out 2>err
  local status=$?
  set -e
  if [[ "$status" != "$expected" ]]; then
    printf 'expected exit %s, got %s for %s
' "$expected" "$status" "$*"
    exit 1
  fi
}
expect 0 --require-typed --rules ox-discarded-result allow.ml
[[ ! -s out && ! -s err ]]
expect 1 --require-typed --rules ox-discarded-result stale.ml
expect 0 --rules ox-public-exception stale.ml
for file in bad blank unknown absent wildcard list placement; do
  expect 1 --rules ox-public-exception "$file.ml"
done
expect 1 --require-typed --rules ox-discarded-result narrow.ml
expect 1 --require-typed --rules ox-obj-magic forbidden.ml
expect 2 --require-typed --rules ox-discarded-result absent.cmt
expect 2 --rules imaginary-rule allow.ml
# Evidence cannot be waived by otherwise valid source decisions.
worktree=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d "$worktree/_build/.policy-evidence.XXXXXX")
case "$scratch" in "$worktree"/_build/.policy-evidence.*) ;; *) exit 2 ;; esac
trap 'rm -rf -- "${scratch:?}"' EXIT
printf '(lang dune 3.17)\n' > "$scratch/dune-project"
printf '(library (name disposal_control) (wrapped false) (modules allow))\n' > "$scratch/dune"
cp allow.ml "$scratch/allow.ml"
chmod u+w "$scratch/allow.ml"
expect 2 --require-typed --rules ox-discarded-result --root "$scratch" "$scratch/allow.ml"
dune build --root "$scratch" @check > "$scratch/build-out" 2> "$scratch/build-err"
expect 0 --require-typed --rules ox-discarded-result --root "$scratch" "$scratch/allow.ml"
# ^safe-pufa: compiler byte offsets move, but authored source coordinates do not.
printf '%s\n' '(library (name disposal_control) (wrapped false) (modules allow) (preprocess (action (run bash %{dep:preprocess.sh} %{input-file}))))' > "$scratch/dune"
printf '%s\n' 'printf "%4096s\n" ""' 'printf "# 1 \"allow.ml\"\n"' 'while IFS= read -r line || test -n "$line"; do printf "%s\n" "$line"; done < "$1"' > "$scratch/preprocess.sh"
dune build --root "$scratch" @check > "$scratch/build-out" 2> "$scratch/build-err"
expect 0 --require-typed --rules ox-discarded-result --root "$scratch" "$scratch/allow.ml"
printf '\n' >> "$scratch/allow.ml"
expect 2 --require-typed --rules ox-discarded-result --root "$scratch" "$scratch/allow.ml"
printf 'checked disposal CLI: pass\n'
