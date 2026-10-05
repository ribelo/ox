#!/usr/bin/env bash
# ^safe-rxya ^safe-d197 ^safe-xd2e ^safe-fr73 ^safe-y047 ^safe-czoe
# ^safe-tlyw ^safe-m5sp ^safe-t37w ^safe-12o2: compiled and installed CLI seam.
set -euo pipefail
here=$(realpath "$(dirname "$0")")
lint=$(realpath "${1:?pass the decider executable}")
clean=$(realpath "${2:-$here/../clean/constant_index.ml}")
violating=$(realpath "${3:-$here/../violating/constant_index.ml}")
# Optional fourth argument is the installed evidence root for --self-check.
installed_root=
if [[ $# -ge 4 ]]; then installed_root=$(realpath "$4"); fi
scratch=$(mktemp -d /var/tmp/ox-constant-index-cli.XXXXXX)
scratch=$(realpath "$scratch")
case "$scratch" in /*/ox-constant-index-cli.*) ;; *) exit 2 ;; esac
[[ -d "$scratch" ]] || exit 2
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT
# Dune may put TMPDIR inside its checkout-shaped sandbox; use /var/tmp directly
# and verify that no ancestor supplies checkout metadata.
ancestor=$scratch
while [[ $ancestor != / ]]; do
  if [[ -f "$ancestor/.git" || -f "$ancestor/.git/HEAD" ]]; then
    printf 'consumer scratch is inside a checkout: %s\n' "$scratch" >&2
    exit 2
  fi
  ancestor=$(dirname "$ancestor")
done
# Absolute binary/assets are resolved above; policy and resources come only from
# this disposable consumer or the explicitly supplied installed evidence root.
cd "$scratch"
expect() {
  local expected=$1 actual; shift
  if "$lint" --rules ox-constant-index "$@" >"$scratch/out" 2>"$scratch/err"; then
    actual=0
  else
    actual=$?
  fi
  if [[ $actual != "$expected" ]]; then
    printf 'expected rc=%s, got rc=%s: %s\n' "$expected" "$actual" "$*" >&2
    cat "$scratch/out" "$scratch/err" >&2
    exit 1
  fi
}
contains() {
  if ! grep -Fq -- "$2" "$1"; then
    printf 'missing expected text: %s\n' "$2" >&2
    cat "$1" >&2
    exit 1
  fi
}
if [[ -n "$installed_root" ]]; then
  expect 0 --self-check --root "$installed_root"
  contains "$scratch/out" "ox-lint --self-check:"
  contains "$scratch/out" "replacement/violating/clean/docs present"
  [[ ! -s "$scratch/err" ]]
fi
printf '(lang dune 3.22)\n' >"$scratch/dune-project"
for kind in clean violating; do
  mkdir "$scratch/$kind"
  printf '(library (name %s) (wrapped false) (modules constant_index))\n' "$kind" >"$scratch/$kind/dune"
done
cp "$clean" "$scratch/clean/constant_index.ml"
cp "$violating" "$scratch/violating/constant_index.ml"
cp "${clean%.ml}.mli" "$scratch/clean/constant_index.mli"
cp "${violating%.ml}.mli" "$scratch/violating/constant_index.mli"
chmod u+w "$scratch/clean/constant_index.ml" "$scratch/violating/constant_index.ml"
dune build --root "$scratch" @check
expect 0 --require-typed "$scratch/clean/constant_index.ml"
[[ ! -s "$scratch/out" && ! -s "$scratch/err" ]]
expect 1 --require-typed "$scratch/violating/constant_index.ml"
[[ $(wc -l <"$scratch/out") == 9 ]]
contains "$scratch/out" ":2: ox-constant-index: constant index 1 is outside [0, 1): proved array length 1"
contains "$scratch/out" 'ox-constant-index: constant index 2 is outside [0, 2): proved string byte length 2'
contains "$scratch/out" 'constant index -1 is outside [0, 1)'
contains "$scratch/out" 'constant index 0 is outside [0, 0)'
contains "$scratch/out" 'raises a defect, not a result error'
expect 1 "$scratch/_build/default/violating/.violating.objs/byte/constant_index.cmt"
# All moves/removals are confined to the verified disposable scratch directory.
cmt="$scratch/_build/default/clean/.clean.objs/byte/constant_index.cmt"
[[ $cmt == "$scratch/"* ]]
mv "$cmt" "$cmt.saved"
expect 2 --require-typed "$scratch/clean/constant_index.ml"
contains "$scratch/err" 'missing typed annotation'
expect 2 "$scratch/clean/constant_index.ml"
contains "$scratch/err" 'missing typed annotation'
mv "$cmt.saved" "$cmt"
printf '\nlet stale = 1\n' >>"$scratch/clean/constant_index.ml"
expect 2 --require-typed "$scratch/clean/constant_index.ml"
contains "$scratch/err" 'stale typed annotation'
# Fresh evidence can still depend on an unavailable imported interface.
mkdir "$scratch/dependency"
printf '(library (name dependency) (wrapped false) (modules getter probe))\n' >"$scratch/dependency/dune"
printf 'val get : int array -> int -> int\n' >"$scratch/dependency/getter.mli"
printf 'let get = Stdlib.Array.get\n' >"$scratch/dependency/getter.ml"
printf '(* Imported identity fixture. *)\n' >"$scratch/dependency/probe.mli"
printf 'let read () = Getter.get [| 1 |] 0\n' >"$scratch/dependency/probe.ml"
dune build --root "$scratch" @check
expect 0 --require-typed "$scratch/dependency/probe.ml"
# Remove every compiled copy from Dune's deliberately redundant CMI paths.
shopt -s globstar nullglob dotglob
for file in "$scratch"/_build/**/getter.cmi; do
  [[ $file == "$scratch/"* ]]
  mv "$file" "$file.saved"
done
expect 2 --require-typed "$scratch/dependency/probe.ml"
contains "$scratch/err" 'missing imported CMI Getter'
printf 'constant index CLI evidence: pass\n'
