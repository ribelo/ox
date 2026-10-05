#!/usr/bin/env bash
set -euo pipefail
# ^safe-czoe ^safe-y047 ^safe-28t6: genuine installation, no checkout fallback.
: "${BIN:?absolute installed ox-lint binary required}"
: "${SHARE:?absolute installed ox_lint share root required}"
: "${STDLIB:?absolute compiler-matched standard-library CMI directory required}"
BIN=$(realpath "$BIN")
SHARE=$(realpath "$SHARE")
STDLIB=$(realpath "$STDLIB")
[ -x "$BIN" ] && [ -f "$STDLIB/stdlib.cmi" ]
outside_checkout() {
  local path=$1
  case "$path" in */_build/*) echo "not installed evidence: $path" >&2; exit 1 ;; esac
  while [ "$path" != / ]; do
    [ ! -e "$path/.git" ] || { echo "checkout evidence forbidden: $path" >&2; exit 1; }
    path=$(dirname "$path")
  done
}
outside_checkout "$BIN"
outside_checkout "$SHARE"
WORK=$(mktemp -d /var/tmp/ox-assertion-installed.XXXXXX)
case "$WORK" in /var/tmp/ox-assertion-installed.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "$WORK"' EXIT
outside_checkout "$WORK"
LOG_DIR=${LOG_DIR:-$(mktemp -d /var/tmp/ox-assertion-installed-logs.XXXXXX)}
mkdir -p "$LOG_DIR"
LOG_DIR=$(realpath "$LOG_DIR")
outside_checkout "$LOG_DIR"
printf 'binary=%s
share=%s
stdlib=%s
consumer=%s
invocation=%s
'   "$BIN" "$SHARE" "$STDLIB" "$WORK/consumer" "$WORK/invocation" > "$LOG_DIR/environment.log"
printf 'case	actual	expected
' > "$LOG_DIR/statuses.tsv"
mkdir -p "$WORK/consumer" "$WORK/invocation"
printf '(lang dune 3.22)
(name installed_assertion_consumer)
' > "$WORK/consumer/dune-project"
for kind in clean violating opaque stale missing; do
  mkdir -p "$WORK/consumer/$kind"
  fixture="$SHARE/test/lint/$kind/assertion_effects"
  case "$kind" in
    opaque) fixture="$SHARE/test/lint/safety_assertion_effects/evidence/opaque" ;;
    stale|missing) fixture="$SHARE/test/lint/clean/assertion_effects" ;;
  esac
  cp "$fixture.ml" "$fixture.mli" "$WORK/consumer/$kind/"
  printf '(library (name %s_case) (modes byte) (flags (:standard -nostdlib -I %s)))
'     "$kind" "$STDLIB" > "$WORK/consumer/$kind/dune"
done
cd "$WORK/invocation"
dune build --root "$WORK/consumer" @check > "$LOG_DIR/consumer-build.stdout.log" 2> "$LOG_DIR/consumer-build.stderr.log"
# Retain compiled truth, then change authored input: strict scans must not rebuild it.
printf '
(* authored source changed after compilation *)
' >> "$WORK/consumer/stale/assertion_effects.ml"
# Remove only the verified missing-case annotation, not its source/build membership.
missing=$(realpath "$WORK/consumer/_build/default/missing/.missing_case.objs/byte/missing_case__Assertion_effects.cmt")
case "$missing" in "$WORK/consumer/_build/default/missing/.missing_case.objs/byte/missing_case__Assertion_effects.cmt") ;; *) exit 1 ;; esac
[ -f "$missing" ]
rm -- "$missing"
expect() {
  local label=$1 want=$2 status=0
  shift 2
  OUT="$LOG_DIR/$label.stdout.log"
  ERR="$LOG_DIR/$label.stderr.log"
  "$@" > "$OUT" 2> "$ERR" || status=$?
  printf '%s	%s	%s
' "$label" "$status" "$want" | tee -a "$LOG_DIR/statuses.tsv"
  if [ "$status" != "$want" ]; then
    printf 'expected exit %s, got %s: %s
' "$want" "$status" "$*" >&2
    sed -n '1,100p' "$OUT" "$ERR" >&2
    exit 1
  fi
}
contains() {
  awk -v text="$1" 'index($0,text) {found=1} END {exit !found}' "$ERR" "$OUT"
}
expect self-check 0 "$BIN" --root "$SHARE" --rules ox-assertion-effects --self-check
for mode in selected repo; do
  flags=(--rules ox-assertion-effects)
  if [ "$mode" = repo ]; then flags=(--repo-gate); fi
  expect "$mode-clean" 0 "$BIN" --root "$SHARE" "${flags[@]}" --require-typed "$WORK/consumer/clean/assertion_effects.ml"
  expect "$mode-violating" 1 "$BIN" --root "$SHARE" "${flags[@]}" --require-typed "$WORK/consumer/violating/assertion_effects.ml"
  contains ox-assertion-effects
  contains -noassert
  expect "$mode-opaque" 2 "$BIN" --root "$SHARE" "${flags[@]}" --require-typed "$WORK/consumer/opaque/opaque.ml"
  contains ox-assertion-effects
  contains 'unverified assertion call'
  expect "$mode-stale" 2 "$BIN" --root "$SHARE" "${flags[@]}" --require-typed "$WORK/consumer/stale/assertion_effects.ml"
  contains 'stale typed annotation'
  expect "$mode-missing" 2 "$BIN" --root "$SHARE" "${flags[@]}" --require-typed "$WORK/consumer/missing/assertion_effects.ml"
  contains 'missing typed annotation'
done
printf 'installed evidence logs: %s
' "$LOG_DIR"
