#!/usr/bin/env bash
# ^safe-eeso ^safe-doj9 ^safe-2led ^safe-fr73 ^safe-y047 ^safe-czoe ^safe-tlyw
# Run AFTER shared registration and installation, with the matching compiler:
# nix develop -c bash test/lint/safety_function_comparison/installed_cli.sh /PREFIX/bin/ox-lint /PREFIX/share/ox_lint
set -euo pipefail
[[ $# == 2 ]] || { printf 'usage: %s INSTALLED_BIN INSTALLED_SHARE\n' "$0" >&2; exit 2; }
engine=$(realpath -e "$1")
assets=$(realpath -e "$2")
[[ -x "$engine" && -d "$assets" ]] || exit 2
[[ $(basename "$engine") == ox-lint && $(basename "$(dirname "$engine")") == bin ]] || exit 2
[[ "$assets" == "$(dirname "$(dirname "$engine")")/share/ox_lint" ]] || exit 2
outside_checkout() {
  local directory=$1
  while :; do
    if [[ -e "$directory/.git" || -f "$directory/dune-project" ]]; then
      printf 'source checkout is not an installed-test location: %s\n' "$directory" >&2
      exit 2
    fi
    [[ "$directory" != / ]] || break
    directory=$(dirname "$directory")
  done
}
outside_checkout "$(dirname "$engine")"
outside_checkout "$assets"
scratch=$(mktemp -d /var/tmp/ox-function-comparison-installed.XXXXXX)
[[ -n "$scratch" && -d "$scratch" && "$scratch" == /var/tmp/ox-function-comparison-installed.* ]] || exit 2
scratch=$(realpath -e "$scratch")
[[ "$scratch" == /var/tmp/ox-function-comparison-installed.* ]] || exit 2
cleanup() {
  case "$scratch" in /var/tmp/ox-function-comparison-installed.*) rm -rf -- "$scratch" ;; *) exit 1 ;; esac
}
trap cleanup EXIT
outside_checkout "$scratch"
cd "$scratch"
expect() {
  local expected=$1 rc=0
  shift
  "$engine" --root "$assets" --rules ox-function-comparison "$@" >"$scratch/out" 2>"$scratch/err" || rc=$?
  if [[ $rc != "$expected" ]]; then
    printf 'expected exit %s, got %s: %s\n' "$expected" "$rc" "$*" >&2
    sed -n '1,80p' "$scratch/out" "$scratch/err" >&2
    exit 1
  fi
}
# Force installed resources, from an independent cwd; no source fallback is allowed.
expect 0 --self-check
mkdir "$scratch/project"
for spec in 'violating bad' 'clean good'; do
  read -r kind name <<<"$spec"
  cp "$assets/test/lint/$kind/function_comparison.ml" "$scratch/project/$name.ml"
  cp "$assets/test/lint/$kind/function_comparison.mli" "$scratch/project/$name.mli"
  chmod u+w "$scratch/project/$name.ml" "$scratch/project/$name.mli"
  (cd "$scratch/project"; ocamlc -bin-annot -c "$name.mli"; ocamlc -bin-annot -c "$name.ml")
done
expect 1 --require-typed "$scratch/project/bad.ml"
# Exactly one diagnostic per supported application; no duplicate partial diagnostics.
awk '/ox-function-comparison:/ { count++ } END { exit count != 17 }' "$scratch/out"
for line in 2 3 4 5 6 7 8 12 16 19 21 25 29 31 36 40 43; do
  awk -v marker="bad.ml:$line:" 'index($0, marker) { found=1 } END { exit !found }' "$scratch/out"
done
awk '/unsupported structural comparison of functions/ { found=1 } END { exit !found }' "$scratch/out"
expect 0 --require-typed "$scratch/project/good.ml"
[[ ! -s "$scratch/out" ]]
# Explicit source evidence is not rebuilt or waived by a clean decision.
printf '\n(* stale evidence control *)\n' >>"$scratch/project/bad.ml"
expect 2 --require-typed "$scratch/project/bad.ml"
awk '/stale|digest|changed/ { found=1 } END { exit !found }' "$scratch/err"
printf 'let same (f : int -> int) g = f = g\n' >"$scratch/project/missing.ml"
expect 2 --require-typed "$scratch/project/missing.ml"
[[ -s "$scratch/err" ]]
printf 'installed function-comparison diagnostics, controls and evidence failures: pass\n'
