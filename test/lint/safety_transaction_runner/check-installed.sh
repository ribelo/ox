#!/usr/bin/env bash
# ^safe-fr73 ^safe-y047 ^safe-t37w ^safe-12o2: genuine installed external CLI/native consumer.
set -eEuo pipefail
unset DUNE_SOURCEROOT DUNE_INSIDE_DUNE INSIDE_DUNE
lint=$(realpath "${1:?absolute genuinely installed ox-lint binary}")
share=$(realpath "${2:?absolute genuinely installed ox_lint share root}")
prefix=$(realpath "${3:?absolute genuinely installed dependency prefix}")
outside_checkout() {
  local target=$1
  case "$target" in */_build/*) printf "build-tree evidence is not installed acceptance: %s\n" "$target" >&2; exit 2 ;; esac
  while [[ "$target" != / ]]; do
    [[ ! -e "$target/.git" ]] || { printf "checkout evidence forbidden: %s\n" "$target" >&2; exit 2; }
    target=$(dirname "$target")
  done
}
outside_checkout "$lint"; outside_checkout "$share"; outside_checkout "$prefix"
[[ -x "$lint" && -f "$prefix/lib/ox_lint/dune-package" && -f "$prefix/lib/ox_sql/dune-package" ]]
assets="$share/test/lint"
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
scratch=$(mktemp -d /var/tmp/ox-transaction-installed.XXXXXXXX)
case "$scratch" in /var/tmp/ox-transaction-installed.*) ;; *) exit 2 ;; esac
trap 'rm -rf -- "$scratch"' EXIT
outside_checkout "$scratch"
expect() {
  local label=$1 expected=$2 actual=0; shift 2
  "$lint" --root "$scratch/consumer" --rules ox-transaction-runner "$@" >"$scratch/out" 2>"$scratch/err" || actual=$?
  printf "installed transaction %-10s actual=%s expected=%s\n" "$label" "$actual" "$expected"
  if [[ "$expected" = 2 ]]; then
    sed -n "1,80p" "$scratch/err"
    [[ ! -s "$scratch/out" ]]
  fi
  if [[ "$actual" != "$expected" ]]; then
    sed -n "1,100p" "$scratch/out" "$scratch/err" >&2; exit 1
  fi
}
mkdir "$scratch/consumer" "$scratch/invocation"
printf "(lang dune 3.22)\n(name installed_transaction_consumer)\n" > "$scratch/consumer/dune-project"
for kind in clean violating undecided wrapper_bad wrapper_clean eager_results; do
  mkdir "$scratch/consumer/$kind"
  fixture="$assets/$kind/transaction_runner"
  case "$kind" in undecided|wrapper_bad|wrapper_clean|eager_results) fixture="$assets/safety_transaction_runner/evidence/$kind" ;; esac
  cp "$fixture.ml" "$scratch/consumer/$kind/transaction_runner.ml"
  cp "$fixture.mli" "$scratch/consumer/$kind/transaction_runner.mli"
  printf "(library (name consumer_%s) (modules transaction_runner) (libraries ox_sql eio_main))\n" "$kind" > "$scratch/consumer/$kind/dune"
done
cd "$scratch/invocation"
"$lint" --root "$share" --self-check
dune build --root "$scratch/consumer" @check
expect violating 1 "$scratch/consumer/violating/transaction_runner.ml"
awk '/transaction_runner.ml:6: ox-transaction-runner/ { found=1 } END {exit !found}' "$scratch/out"
expect clean 0 "$scratch/consumer/clean/transaction_runner.ml"
[[ ! -s "$scratch/out" && ! -s "$scratch/err" ]]
expect undecided 2 "$scratch/consumer/undecided/transaction_runner.ml"
awk '/line 5: ox-transaction-runner/ { found=1 } END {exit !found}' "$scratch/err"
expect wrapper_bad 1 "$scratch/consumer/wrapper_bad/transaction_runner.ml"
[[ $(awk '/transaction_runner.ml:(7|12): ox-transaction-runner/ { n++ } END { print n+0 }' "$scratch/out") = 2 ]]
expect wrapper_clean 0 "$scratch/consumer/wrapper_clean/transaction_runner.ml"
[[ ! -s "$scratch/out" && ! -s "$scratch/err" ]]
actual=0
"$lint" --root "$scratch/consumer" --rules ox-transaction-runner "$scratch/consumer/eager_results/transaction_runner.ml" >"$scratch/out" 2>"$scratch/err" || actual=$?
printf "installed transaction eager_results actual=%s expected=2 (1 defect, 6 located unknowns)\n" "$actual"
[[ "$actual" = 2 ]]
[[ $(awk '/transaction_runner.ml:43: ox-transaction-runner/ { n++ } END { print n+0 }' "$scratch/out") = 1 ]]
[[ $(awk '/ox-transaction-runner: opaque helper receives or captures/ { n++ } END { print n+0 }' "$scratch/err") = 6 ]]
[[ $(awk '/line (18|23|28|33|38|48): ox-transaction-runner/ { n++ } END { print n+0 }' "$scratch/err") = 6 ]]
clean_annotation="$scratch/consumer/_build/default/clean/.consumer_clean.objs/byte/consumer_clean__Transaction_runner.cmt"
violating_annotation="$scratch/consumer/_build/default/violating/.consumer_violating.objs/byte/consumer_violating__Transaction_runner.cmt"
[[ $(realpath "$clean_annotation") = "$clean_annotation" ]]
chmod u+w "$clean_annotation"
cp "$clean_annotation" "$scratch/clean.saved.cmt"
cp "$violating_annotation" "$clean_annotation"
expect mismatched 2 "$scratch/consumer/clean/transaction_runner.ml"
# A foreign CMT may be rejected during source discovery, leaving no admitted typed annotation.
awk '/annotation belongs to another source|annotation compilation unit differs|missing typed annotation/ {found=1} END {exit !found}' "$scratch/err"
cp "$scratch/clean.saved.cmt" "$clean_annotation"
[[ $(realpath "$clean_annotation") = "$clean_annotation" ]]
rm -- "$clean_annotation"
expect missing 2 "$scratch/consumer/clean/transaction_runner.ml"
awk '/missing typed annotation/ {found=1} END {exit !found}' "$scratch/err"
cp "$scratch/clean.saved.cmt" "$clean_annotation"
chmod u+w "$scratch/consumer/clean/transaction_runner.ml"
printf "\n(* source changed after compilation *)\n" >> "$scratch/consumer/clean/transaction_runner.ml"
expect stale 2 "$scratch/consumer/clean/transaction_runner.ml"
awk '/stale typed annotation/ {found=1} END {exit !found}' "$scratch/err"
printf "genuinely installed external CLI accepted; no source/build-tree fallback\n"
