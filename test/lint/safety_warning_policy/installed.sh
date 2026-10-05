#!/usr/bin/env bash
# ^safe-tpzm ^safe-zxc1: genuine installation and external compiled consumer seam.
set -euo pipefail
SCRIPT_DIR=$(dirname "$(realpath -e -- "${BASH_SOURCE[0]}")")
: "${BIN:?absolute installed ox-lint executable}"
: "${SHARE:?absolute installed share/ox_lint bundle root}"
: "${OCAMLC:?absolute pinned compiler executable}"
: "${CMI:?absolute compiler standard-library CMI directory}"
: "${DUNE:?absolute pinned Dune executable}"
for variable in BIN SHARE OCAMLC CMI DUNE; do
  value="${!variable}"
  [[ "$value" = /* ]] || { printf '%s must be absolute\n' "$variable" >&2; exit 2; }
done
[[ -x "$BIN" && -x "$OCAMLC" && -x "$DUNE" && -f "$CMI/stdlib.cmi" ]]
BIN=$(realpath -e -- "$BIN")
SHARE=$(realpath -e -- "$SHARE")
prefix=$(dirname "$(dirname "$BIN")")
outside_repository() {
  local directory
  directory=$(realpath -e -- "$1")
  [[ -d "$directory" ]] || directory=$(dirname "$directory")
  while :; do
    [[ ! -e "$directory/.git" && ! -L "$directory/.git" ]] || {
      printf 'repository ancestor disallowed: %s\n' "$directory" >&2; exit 2;
    }
    [[ "$directory" != / ]] || break
    directory=$(dirname "$directory")
  done
}
# Check every ancestor, including .git files, directories and symlinks.
outside_repository "$prefix"
outside_repository "$BIN"
outside_repository "$SHARE"
[[ "$BIN" = "$prefix/bin/"* && "$SHARE" = "$prefix/"* ]] || {
  echo 'BIN and SHARE must belong to one installed prefix' >&2; exit 2;
}
case "$BIN:$SHARE" in *'/_build/'*) echo 'build-tree paths are not an installation' >&2; exit 2;; esac
for evidence in docs/rules/ox-warning-policy.md test/lint/clean/warning_policy.ml test/lint/clean/warning_policy.mli test/lint/violating/warning_policy.ml test/lint/violating/warning_policy.mli; do
  [[ -f "$SHARE/$evidence" ]] || { echo "missing installed evidence: $evidence" >&2; exit 2; }
done
outside_repository /var/tmp
scratch=$(mktemp -d /var/tmp/ox-warning-installed.XXXXXXXX)
# A fixed mktemp-created absolute directory is the only deletion target.
[[ "$scratch" = /var/tmp/ox-warning-installed.* && -d "$scratch" ]]
trap 'rm -rf -- "${scratch:?}"' EXIT
source "$SCRIPT_DIR/oracle.sh"
mkdir "$scratch/invocation" "$scratch/consumer"
outside_repository "$scratch/consumer"
cd "$scratch/invocation"
outside_repository "$PWD"
# Missing registration/evidence fails here; never borrow a checkout bundle.
"$BIN" --self-check --root "$SHARE"
export PATH="$(dirname "$OCAMLC"):$PATH"
export OCAMLLIB="$CMI"
consumer="$scratch/consumer"
printf '(lang dune 3.21)\n(name installed_warning_policy)\n' > "$consumer/dune-project"
cp "$SHARE/test/lint/clean/warning_policy.ml" "$consumer/restored.ml"
cp "$SHARE/test/lint/clean/warning_policy.mli" "$consumer/restored.mli"
cp "$SHARE/test/lint/violating/warning_policy.ml" "$consumer/bad.ml"
cp "$SHARE/test/lint/violating/warning_policy.mli" "$consumer/bad.mli"
printf 'let value = 1\n' > "$consumer/unrelated.ml"
printf 'val value : int\n' > "$consumer/unrelated.mli"
printf '(library (name consumer) (wrapped false) (modules (:standard \\ unrelated)))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
run() {
  local expected=$1 target=$2 output="$scratch/output" status=0
  local -a typed=()
  if [[ ${3:-typed} != direct ]]; then typed+=(--require-typed); fi
  "$BIN" --root "$SHARE" "${typed[@]}" --rules ox-warning-policy "$target" > "$output" 2>&1 || status=$?
  local wanted
  case "$expected" in
    clean) wanted=0 ;; restriction) wanted=1 ;; unverified) wanted=2 ;;
    *) echo "unknown status expectation: $expected" >&2; exit 1 ;;
  esac
  [[ $status = "$wanted" ]] || {
    printf 'expected %s, got %s: %s\n' "$wanted" "$status" "$target" >&2
    sed -n '1,100p' "$output" >&2; exit 1
  }
  local literal=clean
  if [[ "$expected" != clean ]]; then literal=${ORACLE_CASE:?literal oracle required}; fi
  oracle_assert "$literal" "$target"
}
run clean "$consumer/restored.ml"
run clean "$consumer/restored.mli"
ORACLE_CASE=source-8-two
run restriction "$consumer/bad.ml"
run restriction "$consumer/bad.mli"
# Opposing attached attributes are deliberately separate, not combined floating strings.
printf 'let value = 1 [@@warning "-8"] [@@warning "+8"]\n' > "$consumer/attached_bad.ml"
printf 'let value = 1 [@@warning "+8"] [@@warning "-8"]\n' > "$consumer/attached_clean.ml"
printf 'val value : int\n' > "$consumer/attached_bad.mli"
printf 'val value : int\n' > "$consumer/attached_clean.mli"
(cd "$consumer"; "$DUNE" build @check)
ORACLE_CASE=source-8-one
run restriction "$consumer/attached_bad.ml"
run clean "$consumer/attached_clean.ml"
# Comment/unrelated-stanza edits must remain verified even when @check reuses CMT.
cmt="$consumer/_build/default/.consumer.objs/byte/restored.cmt"
[[ -f "$cmt" ]]
before=$(sha256sum "$cmt")
before_time=$(stat -c '%y' "$cmt")
printf '; non-policy edit\n(library (name unrelated) (wrapped false) (modules unrelated) (flags (:standard -w -8)))\n' >> "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
[[ "$(sha256sum "$cmt")" = "$before" && "$(stat -c '%y' "$cmt")" = "$before_time" ]]
run clean "$consumer/restored.ml"
# Preserving policy-file timestamps must not certify stale compiler settings.
cp -p "$consumer/dune" "$scratch/dune-stamp"
printf '(library (name consumer) (wrapped false) (flags (:standard -w -8)))\n' > "$consumer/dune"
touch -r "$scratch/dune-stamp" "$consumer/dune"
ORACLE_CASE=consumer-flags
run unverified "$consumer/restored.ml"
# Concrete combined Dune restoration is certified from its own compiler command.
printf '(library (name consumer) (wrapped false) (flags (:standard -w -P)) (ocamlc_flags (-w +8)))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
run clean "$consumer/restored.ml"
# An unbuilt release scope cannot be certified by a dev artifact.
printf '(library (name consumer) (wrapped false))\n(env (release (flags (:standard -w -8))))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
ORACLE_CASE=release
run unverified "$consumer/restored.ml"
# Recorded compiler arguments do not resolve a current template content declaration.
printf '(library (name consumer) (wrapped false) (flags (:standard -w %%{env:WARNINGS=+a})))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
ORACLE_CASE=template
run unverified "$consumer/restored.ml"
printf '(library (name consumer) (wrapped false))\n' > "$consumer/dune"
# The compiled consumer remains external; invocation stays in the distinct cwd.
printf 'let value = 1\n' > "$consumer/missing.ml"
printf 'val value : int\n' > "$consumer/missing.mli"
ORACLE_CASE=missing
run unverified "$consumer/missing.ml"
# Current owner and source membership must agree with unchanged recorded ownership.
role="$scratch/ownership"
mkdir "$role"
printf '(lang dune 3.21)\n(name ownership_scope)\n' > "$role/dune-project"
for module in member spare other; do
  printf 'let value = 1\n' > "$role/$module.ml"
  printf 'val value : int\n' > "$role/$module.mli"
done
printf '(library (name foo) (wrapped false) (modules member spare))\n(library (name bar) (wrapped false) (modules other) (flags (:standard -w -8)))\n' > "$role/dune"
(cd "$role"; "${DUNE:-dune}" build @check)
role_cmt="$role/_build/default/.foo.objs/byte/member.cmt"
role_cmti="$role/_build/default/.foo.objs/byte/member.cmti"
role_hash=$(sha256sum "$role/member.ml" "$role/member.mli" "$role_cmt" "$role_cmti")
role_time=$(stat -c '%n:%y' "$role/member.ml" "$role/member.mli" "$role_cmt" "$role_cmti")
run clean "$role_cmt" direct; run clean "$role_cmti" direct
# Retiring/renaming the old owner cannot certify a new weaker owner from old CMT.
ORACLE_CASE=transfer
printf '(library (name renamed) (wrapped false) (modules spare))\n(library (name bar) (wrapped false) (modules member other) (flags (:standard -w -8)))\n' > "$role/dune"
run unverified "$role_cmt" direct; run unverified "$role_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# The old name still exists, but no longer owns the inspected source.
printf '(library (name foo) (wrapped false) (modules spare))\n(library (name bar) (wrapped false) (modules member other) (flags (:standard -w -8)))\n' > "$role/dune"
run unverified "$role_cmt" direct; run unverified "$role_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# A supported literal standard-minus expression preserves genuinely disjoint owners.
printf '(library (name foo) (wrapped false) (modules (:standard \\ other)))\n(library (name bar) (wrapped false) (modules other) (flags (:standard -w -8)))\n' > "$role/dune"
run clean "$role_cmt" direct; run clean "$role_cmti" direct
# Excluding the inspected module with the same expression must invalidate old ownership.
printf '(library (name foo) (wrapped false) (modules (:standard \\ member other)))\n(library (name bar) (wrapped false) (modules member other) (flags (:standard -w -8)))\n' > "$role/dune"
run unverified "$role_cmt" direct; run unverified "$role_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# Even a matching old owner cannot prove an ambiguous or unresolved current assignment.
ORACLE_CASE=owner
printf '(library (name foo) (wrapped false) (modules member spare))\n(library (name bar) (wrapped false) (modules member other))\n' > "$role/dune"
run unverified "$role_cmt" direct; run unverified "$role_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(library (name foo) (wrapped false) (modules member spare))\n(library (name bar) (wrapped false) (modules (:include modules.sexp)))\n' > "$role/dune"
printf '(other)\n' > "$role/modules.sexp"
ORACLE_CASE=unresolved
run unverified "$role_cmt" direct; run unverified "$role_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# A unique default owner is supported, not rejected merely for omitting modules.
printf '(library (name foo) (wrapped false))\n' > "$role/dune"
run clean "$role_cmt" direct; run clean "$role_cmti" direct
[[ "$(sha256sum "$role/member.ml" "$role/member.mli" "$role_cmt" "$role_cmti")" = "$role_hash" ]]
[[ "$(stat -c '%n:%y' "$role/member.ml" "$role/member.mli" "$role_cmt" "$role_cmti")" = "$role_time" ]]
# Explicit shared test helpers retain a unique recorded role and every sharing guard.
sharing="$scratch/sharing"
mkdir "$sharing"
printf '(lang dune 3.21)\n(name shared_roles)\n' > "$sharing/dune-project"
for module in first second helper; do
  printf 'let value = 1\n' > "$sharing/$module.ml"
  printf 'val value : int\n' > "$sharing/$module.mli"
done
printf '(test (name first) (modules first helper))\n(test (name second) (modules second helper))\n' > "$sharing/dune"
(cd "$sharing"; "${DUNE:-dune}" build @check)
sharing_cmt="$sharing/_build/default/.first.eobjs/byte/dune__exe__Helper.cmt"
sharing_cmti="$sharing/_build/default/.first.eobjs/byte/dune__exe__Helper.cmti"
sharing_second_cmt="$sharing/_build/default/.second.eobjs/byte/dune__exe__Helper.cmt"
sharing_second_cmti="$sharing/_build/default/.second.eobjs/byte/dune__exe__Helper.cmti"
sharing_hash=$(sha256sum "$sharing/helper.ml" "$sharing/helper.mli" "$sharing_cmt" "$sharing_cmti")
sharing_time=$(stat -c '%n:%y' "$sharing/helper.ml" "$sharing/helper.mli" "$sharing_cmt" "$sharing_cmti")
run clean "$sharing_cmt" direct; run clean "$sharing_cmti" direct
run clean "$sharing_second_cmt" direct; run clean "$sharing_second_cmti" direct
# A different sharing name is not disjoint: its weaker guard must be rejected.
ORACLE_CASE=sharing-weak
printf '(test (name first) (modules first helper))\n(test (name second) (modules second helper) (flags (:standard -w -8)))\n' > "$sharing/dune"
run unverified "$sharing_cmt" direct; run unverified "$sharing_cmti" direct
grep -q 'disagrees with recorded compiler warning settings' "$scratch/output"
# Unknown/default overlap cannot borrow the finite explicit-sharing proof.
printf '(test (name first) (modules first helper))\n(test (name second) (modules (:include modules.sexp)))\n' > "$sharing/dune"
printf '(second helper)\n' > "$sharing/modules.sexp"
ORACLE_CASE=unresolved
run unverified "$sharing_cmt" direct; run unverified "$sharing_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(test (name second))\n' > "$sharing/dune"
ORACLE_CASE=owner
run unverified "$sharing_cmt" direct; run unverified "$sharing_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# Sharing does not repair exclusion from the exact recorded role or duplicate owners.
printf '(test (name first) (modules first))\n(test (name second) (modules second helper))\n' > "$sharing/dune"
run unverified "$sharing_cmt" direct; run unverified "$sharing_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(test (name first) (modules second helper))\n' > "$sharing/dune"
run unverified "$sharing_cmt" direct; run unverified "$sharing_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(tests (names second second) (modules second helper))\n' > "$sharing/dune"
run unverified "$sharing_cmt" direct; run unverified "$sharing_cmti" direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(test (name second) (modules second helper))\n' > "$sharing/dune"
run clean "$sharing_cmt" direct; run clean "$sharing_cmti" direct
[[ "$(sha256sum "$sharing/helper.ml" "$sharing/helper.mli" "$sharing_cmt" "$sharing_cmti")" = "$sharing_hash" ]]
[[ "$(stat -c '%n:%y' "$sharing/helper.ml" "$sharing/helper.mli" "$sharing_cmt" "$sharing_cmti")" = "$sharing_time" ]]
check_source_control() {
  ORACLE_CASE=$3
  case "$1" in
    0) run clean "$2" ;; 1) run restriction "$2" ;; 2) run unverified "$2" ;;
  esac
}
SOURCE_FIXTURES="$SHARE/test/lint/safety_warning_policy/negative"
source "$SCRIPT_DIR/source_controls.sh"
check_annotation() {
  ORACLE_CASE=${3:-owner}
  if [[ "$1" = 0 ]]; then run clean "$2" direct; else run unverified "$2" direct; fi
}
source "$SCRIPT_DIR/reorder.sh"
echo 'installed warning policy: compiled restrictions, restoration, current ownership, shared-role guards and unknown scopes verified'
