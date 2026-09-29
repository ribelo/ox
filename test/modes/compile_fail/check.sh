#!/usr/bin/env bash
# nwake-8qx5: a missing random source must be a type error, not a runtime defect.
set -euo pipefail
ocamlc="$1"
include="$(cd "$2" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp:?}"' EXIT
compile() {
  cp "$1" "$tmp/"
  (cd "$tmp" && "$ocamlc" -I "$include" -c "$1") >"$tmp/out" 2>&1
}
if ! compile control.ml; then
  printf 'FAIL: explicit sources should compile\n'
  cat "$tmp/out"
  exit 1
fi
printf 'ok: all explicit jitter sources compile\n'
for source in jittered.ml jitter_kind.ml decorrelated.ml; do
  if compile "$source"; then
    printf 'FAIL: %s compiled without random\n' "$source"
    exit 1
  fi
  if ! grep -q 'random:Random.State.t' "$tmp/out"; then
    printf 'FAIL: %s refused for an unrelated reason\n' "$source"
    cat "$tmp/out"
    exit 1
  fi
  printf 'ok: %s refused without required random\n' "$source"
done
