#!/usr/bin/env bash
# ^safe-9gfb ^safe-tlyw ^safe-fr73: run after shared registration and installation.
# Usage: bash check-installed.sh /prefix/bin/ox-lint /prefix/share/ox_lint
# Needs the compiler that built the installed linter. Both paths must be installed
# outside a source checkout; consumer compilation and invocation run in /var/tmp.
set -eEuo pipefail
[[ "$#" = 2 ]] || { printf 'usage: %s INSTALLED_BIN INSTALLED_SHARE\n' "$0" >&2; exit 2; }
lint="$(realpath -e "$1")"
assets="$(realpath -e "$2")"
[[ -x "$lint" && -d "$assets" ]] || exit 2
[[ "$(basename "$lint")" = ox-lint && "$(basename "$(dirname "$lint")")" = bin ]] || exit 2
[[ "$assets" = "$(dirname "$(dirname "$lint")")/share/ox_lint" ]] || exit 2
outside_checkout() {
  local directory="$1"
  while :; do
    if [[ -e "$directory/.git" || -f "$directory/dune-project" ]]; then
      printf 'source checkout is not an installed-test location: %s\n' "$directory" >&2
      exit 2
    fi
    [[ "$directory" != / ]] || break
    directory="$(dirname "$directory")"
  done
}
outside_checkout "$(dirname "$lint")"
outside_checkout "$assets"
scratch="$(mktemp -d /var/tmp/ox-identity-installed.XXXXXX)"
[[ -n "$scratch" && -d "$scratch" && "$scratch" = /var/tmp/ox-identity-installed.* ]] || exit 2
# Verified mktemp directory only; never remove a computed repository path.
trap 'rm -rf -- "$scratch"' EXIT
outside_checkout "$scratch"
cd "$scratch"
expect() {
  local expected="$1"; shift
  local got=0
  "$lint" --root "$assets" --rules ox-identity-external "$@" >"$scratch/out" 2>"$scratch/err" || got=$?
  if [[ "$got" != "$expected" ]]; then
    printf 'expected rc=%s, got rc=%s: %s\n' "$expected" "$got" "$*" >&2
    cat "$scratch/out" "$scratch/err" >&2
    exit 1
  fi
}
# Force resource validation against the supplied installed share, never a checkout.
expect 0 --self-check
for kind in violating clean; do
  mkdir "$scratch/$kind"
  cp "$assets/test/lint/$kind/identity_external."{ml,mli} "$scratch/$kind/"
  chmod u+w "$scratch/$kind/identity_external."{ml,mli}
  (cd "$scratch/$kind" && ocamlc -bin-annot -c identity_external.mli &&
    ocamlc -bin-annot -c identity_external.ml)
  expected=0
  [[ "$kind" = clean ]] || expected=1
  for extension in ml mli; do
    expect "$expected" --require-typed "$scratch/$kind/identity_external.$extension"
    if [[ "$expected" = 1 ]]; then
      [[ "$(wc -l < "$scratch/out")" = 6 ]]
      for line in 2 3 6 14 18 22; do
        grep -q ":$line: ox-identity-external:" "$scratch/out"
      done
    else
      [[ ! -s "$scratch/out" && ! -s "$scratch/err" ]]
    fi
  done
done
# Primitive policy is checked even without requesting typed evidence.
expect 1 "$scratch/violating/identity_external.ml"
mkdir "$scratch/missing"
cp "$scratch/clean/identity_external."{ml,mli} "$scratch/missing/"
for extension in ml mli; do
  expect 2 --require-typed "$scratch/missing/identity_external.$extension"
  grep -q 'missing typed annotation' "$scratch/err"
done
# Change content, not just timestamps, to deterministically stale both annotations.
printf '\n(* changed after compilation *)\n' >> "$scratch/clean/identity_external.ml"
printf '\n(* changed after compilation *)\n' >> "$scratch/clean/identity_external.mli"
for extension in ml mli; do
  expect 2 --require-typed "$scratch/clean/identity_external.$extension"
  grep -q 'stale typed annotation' "$scratch/err"
done
[[ -f "$assets/docs/rules/ox-identity-external.md" ]]
printf 'installed identity external checks passed\n'
