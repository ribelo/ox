#!/usr/bin/env bash
# ^safe-fr73 ^safe-tlyw: acceptance consumes a real external installation only.
# Manual: bash check-cli.sh /absolute/external/installed/prefix
# Optional alias: OX_IO_COUNT_INSTALLED_PREFIX=/absolute/external/prefix
#   nix develop -c dune build @test/lint/safety_io_count/io-count-cli
# Neither source trees nor _build/install are installations for this test.
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 2; }

outside_checkout() {
  local resolved current
  resolved="$(realpath -- "$1")" || die "cannot resolve outside-checkout path: $1"
  current="$resolved"
  while :; do
    if [[ -e "$current/.git" || -L "$current/.git" || -e "$current/.hg" || -e "$current/.svn" ]]; then
      die "path is inside a checkout: $resolved (marker in $current)"
    fi
    [[ "$current" == / ]] && break
    current="$(dirname -- "$current")"
  done
}

[[ $# == 1 && -n "$1" && -d "$1" ]] || die "usage: $0 ABSOLUTE_EXTERNAL_INSTALLED_PREFIX"
[[ "$1" == /* ]] || die "installed prefix must be absolute"
prefix="$(realpath -- "$1")"
outside_checkout "$prefix"
[[ -x "$prefix/bin/ox-lint" && -f "$prefix/share/ox_lint/docs/rules/ox-io-count.md" ]] ||
  die "missing installed ox-lint or ox-io-count rule page in $prefix"
[[ -d "$prefix/lib/ox_caps" ]] || die "missing installed ox_caps in $prefix"
lint="$(realpath -- "$prefix/bin/ox-lint")"
assets="$(realpath -- "$prefix/share/ox_lint")"
outside_checkout "$lint"
outside_checkout "$assets"
outside_checkout "$prefix/lib/ox_caps"
outside_checkout "$assets/docs/rules/ox-io-count.md"
for group in clean violating; do
  for extension in ml mli; do
    fixture="$assets/test/lint/$group/io_count.$extension"
    [[ -f "$fixture" ]] || die "missing installed fixture: $fixture"
    outside_checkout "$fixture"
  done
done
# Preserve dependency packages supplied by the pinned compiler environment, but
# do not permit OCAMLPATH to fall back to a package in any source checkout.
IFS=: read -r -a dependencies <<< "${OCAMLPATH:-}"
for dependency in "${dependencies[@]}"; do
  [[ -z "$dependency" ]] || outside_checkout "$dependency"
done
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"

# /tmp has a checkout marker on the integration machine; use /var/tmp explicitly.
scratch="$(mktemp -d /var/tmp/ox-io-count-installed.XXXXXXXX)"
[[ "$scratch" == /var/tmp/ox-io-count-installed.* && "${scratch%/*}" == /var/tmp ]] ||
  die "unexpected scratch path: $scratch"
[[ "$(realpath -- "$scratch")" == "$scratch" ]] || die "scratch is not canonical: $scratch"
cleanup() {
  # Revalidate the exact absolute deletion target, including its immediate parent.
  [[ "$scratch" == /var/tmp/ox-io-count-installed.* && "${scratch%/*}" == /var/tmp &&
     "$(realpath -- "$scratch")" == "$scratch" ]] || return 2
  rm -rf -- "$scratch"
}
trap cleanup EXIT
outside_checkout "$scratch"
consumer="$scratch"
printf '%s\n' '(lang dune 3.21)' '(name installed_io_count_consumer)' > "$consumer/dune-project"
printf '%s\n' '(library' ' (name cases)' ' (modules clean violating)'   ' (libraries unix ox_caps eio))' > "$consumer/dune"
cp "$assets/test/lint/clean/io_count.ml" "$consumer/clean.ml"
cp "$assets/test/lint/clean/io_count.mli" "$consumer/clean.mli"
cp "$assets/test/lint/violating/io_count.ml" "$consumer/violating.ml"
cp "$assets/test/lint/violating/io_count.mli" "$consumer/violating.mli"
mkdir "$consumer/gate"
printf '%s\n' '(library (name pure) (modules pure))' > "$consumer/gate/dune"
printf '%s\n' 'let plain = 1' > "$consumer/gate/pure.ml"
printf '%s\n' 'val plain : int' > "$consumer/gate/pure.mli"
cd "$consumer"
outside_checkout "$(pwd -P)"
[[ "$(pwd -P)" == "$consumer" ]] || die "unexpected consumer compilation cwd"
dune build

run_lint() {
  local invocation_cwd
  invocation_cwd="$(pwd -P)"
  [[ "$invocation_cwd" == "$consumer" ]] || die "unexpected installed CLI cwd: $invocation_cwd"
  outside_checkout "$invocation_cwd"
  "$lint" --root "$assets" "$@"
}
run_lint --self-check > self-check-output 2>&1
run_lint --require-typed --rules ox-io-count clean.ml
set +e
run_lint --require-typed --rules ox-io-count violating.ml > findings 2>&1
status=$?
set -e
[[ $status == 1 ]] || { printf 'expected finding exit 1, got %s\n' "$status" >&2; exit 1; }

# All registered rules, no filtered selector and no inventory/directory exemption.
run_lint --repo-gate --require-typed --inventory gate/pure.ml gate/pure.mli > gate-output 2>&1
# An explicitly absent typed artifact cannot be silently treated as a clean source.
[[ ! -e "$consumer/missing.cmt" && ! -L "$consumer/missing.cmt" ]] || die "missing-CMT witness exists"
set +e
run_lint --repo-gate --require-typed "$consumer/missing.cmt" > missing-output 2>&1
status=$?
set -e
[[ $status == 2 ]] || { printf 'expected missing-CMT exit 2, got %s\n' "$status" >&2; exit 1; }
python3 - "$assets" <<'PY'
import pathlib, re, sys
assets = pathlib.Path(sys.argv[1])
text = pathlib.Path('findings').read_text()
# Independent harness-owned line/category oracle; installed CLI reports no columns.
expected = [
    (2, 'stream/descriptor'), (5, 'stream/descriptor'), (9, 'stream/descriptor'),
    (12, 'socket'), (15, 'socket'), (19, 'datagram'), (23, 'datagram'),
    (26, 'datagram'), (29, 'stream/descriptor'), (33, 'stream/descriptor'),
    (37, 'datagram'), (41, 'stream/descriptor'), (45, 'stream/descriptor'),
    (49, 'stream/descriptor'), (52, 'stream/descriptor'), (57, 'stream/descriptor'),
    (61, 'stream/descriptor'), (69, 'datagram'), (78, 'stream/descriptor'),
    (79, 'stream/descriptor'), (80, 'stream/descriptor'), (83, 'stream/descriptor'),
    (87, 'stream/descriptor'), (92, 'stream/descriptor'), (97, 'datagram'),
    (103, 'datagram'), (108, 'stream/descriptor'),
]
actual = [(int(line), kind) for line, kind in re.findall(
    r'violating[.]ml:([0-9]+): ox-io-count: (stream/descriptor|socket|datagram) byte count discarded:', text)]
assert sorted(actual) == sorted(expected), (expected, actual, text)
assert text.count('ox-io-count:') == len(expected), text
assert 'ox-io-count:' in text, text
assert 'stream/descriptor byte count discarded:' in text, text
assert 'zero progress' in text, text
assert 'socket byte count discarded:' in text, text
assert 'never loop-until-full' in text, text
assert 'datagram byte count discarded:' in text, text
assert 'do not loop-until-full or split the message' in text, text
self_check = pathlib.Path('self-check-output').read_text()
gate = pathlib.Path('gate-output').read_text()
registered = re.search(r'ox-lint --self-check: ([0-9]+) rule[(]s[)]', self_check)
selected = re.search(r'repo-gate: ([0-9]+) registered rules selected', gate)
assert registered and selected and registered.group(1) == selected.group(1), (self_check, gate)
assert int(selected.group(1)) > 1, gate
assert '0 findings; 0 modules with typed rules undecided' in gate, gate
for source in ('gate/pure.ml', 'gate/pure.mli'):
    assert any(line.startswith(source + '\tdecided\t') for line in gate.splitlines()), gate
missing = pathlib.Path('missing-output').read_text()
assert 'missing.cmt' in missing and re.search(r'No such file|not found|cannot read|missing (annotation|typed|artifact|CMT)', missing), missing
PY
printf '%s\n' 'installed ox-io-count acceptance: clean=0 violating=1 repo-gate=0 missing-CMT=2'
