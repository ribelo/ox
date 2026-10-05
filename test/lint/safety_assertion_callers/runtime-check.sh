#!/usr/bin/env bash
set -euo pipefail
# ^safe-pcom ^safe-28t6: real caller executables, valid evidence and missing evidence.
ROOT=$(realpath "$1")
BIN=$(pwd -P)
WORK=$(mktemp -d "$BIN/runtime.XXXXXX")
case "$WORK" in "$BIN"/runtime.*) ;; *) exit 1 ;; esac
test "$(realpath "$WORK")" = "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/test/lint" "$WORK/test/caps"
cp -aL "$ROOT/docs" "$ROOT/scripts" "$WORK/"
cp -aL "$ROOT/test/lint/clean" "$ROOT/test/lint/violating" "$ROOT/test/lint/entry" "$ROOT/test/lint/syntax_fixture.ml" "$ROOT/test/lint/syntax_fixture.mli" "$WORK/test/lint/"
cp -aL "$ROOT/test/caps/rules" "$WORK/test/caps/"
expect_failure() {
  local directory=$1 executable=$2 expected=$3 output status
  if output=$(cd "$directory" && "$executable" 2>&1); then
    printf 'missing evidence accepted by %s\n' "$executable" >&2
    exit 1
  else
    status=$?
  fi
  if [[ "$status" != 2 || "$output" != *"$expected"* ]]; then
    printf 'unexpected failure from %s: %s\n' "$executable" "$output" >&2
    exit 1
  fi
}
for mode in normal noassert; do
  "$BIN/$mode/callback.exe"
  if [ "$mode" = normal ]; then
    engine="$ROOT/test/lint/test_engine.exe"
    concurrency="$ROOT/test/lint/test_concurrency.exe"
    caps="$ROOT/test/caps/rules/test_caps.exe"
  else
    engine="$BIN/noassert/engine.exe"
    concurrency="$BIN/noassert/concurrency.exe"
    caps="$BIN/noassert/caps.exe"
  fi
  (cd "$WORK/test/lint" && "$engine" && "$concurrency")
  (cd "$WORK/test/caps/rules" && "$caps")
  # All original runner success paths execute. Remove evidence without changing callers.
  evidence="$WORK/docs/rules/ox-discarded-result.md"
  test -f "$evidence"
  test "$(realpath "$evidence")" = "$evidence"
  test "$(realpath -m "$evidence.saved")" = "$evidence.saved"
  mv -- "$evidence" "$evidence.saved"
  expect_failure "$WORK/test/lint" "$engine" "valid rule evidence rejected"
  expect_failure "$WORK/test/lint" "$concurrency" "concurrency rule evidence rejected"
  test "$(realpath "$evidence.saved")" = "$evidence.saved"
  test "$(realpath -m "$evidence")" = "$evidence"
  mv -- "$evidence.saved" "$evidence"
  evidence="$WORK/docs/caps.md"
  test -f "$evidence"
  test "$(realpath "$evidence")" = "$evidence"
  test "$(realpath -m "$evidence.saved")" = "$evidence.saved"
  mv -- "$evidence" "$evidence.saved"
  expect_failure "$WORK/test/caps/rules" "$caps" "capability policy evidence rejected"
  test "$(realpath "$evidence.saved")" = "$evidence.saved"
  test "$(realpath -m "$evidence")" = "$evidence"
  mv -- "$evidence.saved" "$evidence"
done
printf 'actual assertion callers: normal/noassert evaluation and failure agree\n'
