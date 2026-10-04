#!/usr/bin/env bash
# ^ncapslint-w2tq ^ncapslint-x3gi ^ncapslint-87ld: installed shell contract,
# exact pinned IDs, mandatory parser, optional typed census, no other backend.
set -uo pipefail
gate="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
work="$(mktemp -d /tmp/ox-caps-gate.XXXXXXXX)"
trap 'case "$work" in /tmp/ox-caps-gate.*) rm -rf "${work:?}";; esac' EXIT
status=0
tar --exclude=.formatted -cf - violating clean skip-clean skip-violating door-dependency door-access stream-violating shadowed mint-library mint-entry | (cd "$work" && tar -xf -)
check() {
  local fixture="$1" expected="$2" pattern="$3"; shift 3
  (cd "$work/$fixture" && bash "$gate" "$@") >"$work/$fixture.out" 2>&1
  local code=$?
  if [[ "$code" -ne "$expected" ]] || ! grep -q "$pattern" "$work/$fixture.out"; then
    echo "FAIL: $fixture exit $code, wanted $expected / $pattern"; cat "$work/$fixture.out"; status=1
  else echo "ok: $fixture exits $code"; fi
}
check violating 1 'ox-caps-fork'
expected="ox-caps-chdir ox-caps-env ox-caps-exec ox-caps-exit ox-caps-forge ox-caps-fork ox-caps-fs-read ox-caps-fs-write ox-caps-mint ox-caps-network ox-caps-random ox-caps-signal ox-caps-stderr ox-caps-stdin ox-caps-stdout ox-caps-time ox-caps-tmp"
found="$(grep -o 'ox-caps-[a-z-]*' "$work/violating.out" | sort -u | tr '\n' ' ' | sed 's/ $//')"
if [[ "$found" != "$expected" ]] || grep -q raw_test.ml "$work/violating.out" || ! grep -q 'lib/raw.ml:22: ox-caps-fork' "$work/violating.out"; then
  echo "FAIL: exact pinned IDs, tests exclusion or ignored inline suppression"; status=1
fi
check clean 0 'typed rules undecided'
check violating 0 '0 findings' --allow lib/raw.ml
check skip-clean 0 '0 findings'
check skip-violating 1 'ox-caps-fork'
check door-dependency 1 'ox-caps-mint'
check door-access 1 'ox-caps-mint'
check stream-violating 1 'ox-caps-fs-write'
check shadowed 0 '0 findings'
check mint-library 1 'ox-caps-mint'
check mint-entry 0 '0 findings'
check mint-entry 0 '0 findings' "$work/mint-entry"
check mint-library 1 'ox-caps-mint' "$work/mint-library"
check violating 0 '0 findings' --allow lib/raw.ml "$work/violating"
check door-dependency 1 'ox-caps-mint' "$work/door-dependency"
mkdir -p "$work/malformed/lib"
printf 'let broken =\n' >"$work/malformed/lib/broken.ml"
check malformed 2 'lib/broken.ml:1: ox-lint:'
check clean 2 'missing typed annotation' --require-typed
exit "$status"
