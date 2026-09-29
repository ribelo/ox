#!/usr/bin/env bash
# ^ncaps-aw5n ^ncaps-vlwm: compile each case against the installed ox_caps interface.
# Usage: check.sh OCAMLC INCLUDE_DIR. A "fails" case must be refused by the type checker
# with the expected message; a "compiles" case is the control that proves the harness.
set -uo pipefail
ocamlc="$1"
include="$(cd "$2" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
status=0

compile() {
  cp "$1" "$tmp/"
  (cd "$tmp" && "$ocamlc" -I "$include" -I +unix -c "$(basename "$1")") >"$tmp/out" 2>&1
}

compiles() {
  if compile "$1"; then
    echo "ok: $1 compiles"
  else
    echo "FAIL: $1 should compile:"
    cat "$tmp/out"
    status=1
  fi
}

fails() {
  if compile "$1"; then
    echo "FAIL: $1 compiled but must be refused"
    status=1
  elif grep -q -- "$2" "$tmp/out"; then
    echo "ok: $1 refused ($2)"
  else
    echo "FAIL: $1 refused for another reason than '$2':"
    cat "$tmp/out"
    status=1
  fi
}

compiles included.ml
fails excluded.ml "has no method exec"
fails forged.ml "Cap.Token.exec"
compiles portable_control.ml
fails portable.ml "nonportable"
exit "$status"
