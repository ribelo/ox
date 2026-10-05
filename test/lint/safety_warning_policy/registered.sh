#!/usr/bin/env bash
# ^safe-tpzm ^safe-zxc1: registered CLI regressions for real compiler ownership.
set -euo pipefail
SCRIPT_DIR=$(dirname "$(realpath -e -- "${BASH_SOURCE[0]}")")
BIN=$(realpath -e -- "${BIN:-${1:?registered candidate executable}}")
ROOT=$(realpath -e -- "${ROOT:-${2:?candidate evidence root}}")
[[ "$BIN" = /* && "$ROOT" = /* ]]
scratch=$(mktemp -d /var/tmp/ox-warning-registered.XXXXXXXX)
[[ "$scratch" = /var/tmp/ox-warning-registered.* && -d "$scratch" ]]
trap 'rm -rf -- "${scratch:?}"' EXIT
source "$SCRIPT_DIR/oracle.sh"
expect() {
  local expected=$1 target=$2 rules=${3:-ox-warning-policy} status=0
  local -a selected=()
  if [[ "$rules" != all ]]; then IFS=, read -ra selected <<< "$rules"; fi
  local -a options=()
  # Direct typed annotation controls avoid describe-rules repairing generated bodies.
  if [[ ${4:-typed} != direct ]]; then options+=(--require-typed); fi
  local rule
  for rule in "${selected[@]}"; do options+=(--rules "$rule"); done
  "$BIN" --root "$ROOT" "${options[@]}" "$target" > "$scratch/output" 2>&1 || status=$?
  [[ "$status" = "$expected" ]] || { printf 'expected %s, got %s: %s\n' "$expected" "$status" "$target" >&2; sed -n '1,90p' "$scratch/output" >&2; exit 1; }
  local literal=clean
  if [[ "$expected" != 0 ]]; then literal=${ORACLE_CASE:?literal oracle required}; fi
  oracle_assert "$literal" "$target"
}
# A directory called dune is not a policy file, even in a source ancestor.
mkdir "$scratch/dune" "$scratch/standalone"
printf 'let value = 1\n' > "$scratch/standalone/value.ml"
(cd "$scratch/standalone"; ocamlc -bin-annot -warn-error +a -c value.ml)
expect 0 "$scratch/standalone/value.cmt"
(cd "$scratch/standalone"; ocamlc -bin-annot -warn-error -a -c value.ml)
ORACLE_CASE=fatal-all
expect 1 "$scratch/standalone/value.cmt"
# Dune executable implicit opens must survive warning attribute inspection.
mkdir "$scratch/executable"
printf '(lang dune 3.21)\n(name executable_scope)\n' > "$scratch/executable/dune-project"
printf '(executable (name main) (modules main support))\n' > "$scratch/executable/dune"
printf 'let value = 1\n' > "$scratch/executable/support.ml"
printf 'let () = ignore (Ok Support.value)\n' > "$scratch/executable/main.ml"
(cd "$scratch/executable"; dune build @check)
ORACLE_CASE=discarded
expect 1 "$scratch/executable/main.ml" all
grep -q 'ox-discarded-result:' "$scratch/output"
! grep -q 'Cannot find module\|unverified\|undecided' "$scratch/output"
printf 'let () = ignore (Ok (Support.value + 1))\n' > "$scratch/executable/main.ml"
ORACLE_CASE=stale-source
expect 2 "$scratch/executable/main.ml"
grep -q 'stale\|changed\|digest\|source' "$scratch/output"
# Dune's direct empty preprocessed interface needs physical and producer proof.
printf 'let () = ignore (Ok Support.value)\n' > "$scratch/executable/main.ml"
printf '(executable (name main) (modules main support) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/executable/dune"
(cd "$scratch/executable"; dune build @check)
generated="$scratch/executable/_build/default/.main.eobjs/byte/dune__exe__Main.cmti"
body="$scratch/executable/_build/default/main.pp.mli"
expect 0 "$generated"
cp "$body" "$scratch/empty-interface"
# Detach Dune cache hardlinks before deliberately corrupting this scratch body.
[[ "$body" = "$scratch/executable/_build/default/main.pp.mli" ]]
rm -- "$body"
cp "$scratch/empty-interface" "$body"
chmod u+w "$body"
printf '[@@@warning "-8"]\n' > "$body"
ORACLE_CASE=stale-generated
expect 2 "$generated" ox-warning-policy direct
grep -q 'digest\|stale' "$scratch/output"
cp "$scratch/empty-interface" "$body"
printf '(executable (name main) (modules main support) (empty_module_interface false) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/executable/dune"
ORACLE_CASE=generated-owner
expect 2 "$generated" ox-warning-policy direct
grep -q 'generated empty interface producer/unit ownership' "$scratch/output"
printf '(executable (name main) (modules main support) (flags (:standard -w -8)) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/executable/dune"
ORACLE_CASE=generated-flags
expect 2 "$generated" ox-warning-policy direct
grep -q 'disagrees with recorded compiler warning settings' "$scratch/output"
(cd "$scratch/executable"; dune build @check)
ORACLE_CASE=generated-restriction
expect 1 "$generated"
grep -q 'required active/fatal warnings disabled: 8' "$scratch/output"
# Distinct compiler object scopes establish unrelated library ownership.
mkdir "$scratch/libraries"
printf '(lang dune 3.21)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
# Foreign include-based C warning flags are not OCaml warning flags.
printf '(library (name selected) (wrapped false) (modules selected) (foreign_stubs (language c) (names foreign_helper) (flags (:standard (:include c_flags.sexp)))))\n(library (name unrelated) (wrapped false) (modules unrelated) (flags (:standard -w -8)))\n' > "$scratch/libraries/dune"
printf '(-w)\n' > "$scratch/libraries/c_flags.sexp"
printf 'int foreign_helper(void) { return 0; }\n' > "$scratch/libraries/foreign_helper.c"
printf 'let value = 1\n' > "$scratch/libraries/selected.ml"
printf 'val value : int\n' > "$scratch/libraries/selected.mli"
printf 'let value = 1\n' > "$scratch/libraries/unrelated.ml"
(cd "$scratch/libraries"; dune build @check selected.cma)
expect 0 "$scratch/libraries/selected.ml"
expect 0 "$scratch/libraries/selected.mli"
ORACLE_CASE=compiled-8
expect 1 "$scratch/libraries/unrelated.ml"
# Direct compiler metadata cannot assert which Dune library owns it.
printf 'let value = 1\n' > "$scratch/libraries/unowned.ml"
(cd "$scratch/libraries"; ocamlc -bin-annot -warn-error +a -c unowned.ml)
ORACLE_CASE=owner
expect 2 "$scratch/libraries/unowned.cmt"
grep -q 'no exact checked compiler scope' "$scratch/output"
# Verify the audited language transition without lowering root protection.
printf '(lang dune 3.22)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
(cd "$scratch/libraries"; dune build @check)
expect 0 "$scratch/libraries/selected.ml"
printf '(lang dune 3.20)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
(cd "$scratch/libraries"; dune build @check)
ORACLE_CASE=legacy
expect 1 "$scratch/libraries/selected.ml"
grep -q 'required active/fatal warnings disabled' "$scratch/output"
! grep -q 'unverified\|undecided' "$scratch/output"
printf '(library (name selected) (wrapped false) (modules selected) (flags (:standard -warn-error +a)))\n(library (name unrelated) (wrapped false) (modules unrelated) (flags (:standard -w -8)))\n' > "$scratch/libraries/dune"
(cd "$scratch/libraries"; dune build @check)
expect 0 "$scratch/libraries/selected.ml"
printf '(lang dune 3.23)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
ORACLE_CASE=language
expect 2 "$scratch/libraries/selected.ml"
grep -q 'unverified Dune language standard: 3.23' "$scratch/output"
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
expect 0 "$role_cmt" ox-warning-policy direct; expect 0 "$role_cmti" ox-warning-policy direct
# Retiring/renaming the old owner cannot certify a new weaker owner from old CMT.
ORACLE_CASE=transfer
printf '(library (name renamed) (wrapped false) (modules spare))\n(library (name bar) (wrapped false) (modules member other) (flags (:standard -w -8)))\n' > "$role/dune"
expect 2 "$role_cmt" ox-warning-policy direct; expect 2 "$role_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# The old name still exists, but no longer owns the inspected source.
printf '(library (name foo) (wrapped false) (modules spare))\n(library (name bar) (wrapped false) (modules member other) (flags (:standard -w -8)))\n' > "$role/dune"
expect 2 "$role_cmt" ox-warning-policy direct; expect 2 "$role_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# A supported literal standard-minus expression preserves genuinely disjoint owners.
printf '(library (name foo) (wrapped false) (modules (:standard \\ other)))\n(library (name bar) (wrapped false) (modules other) (flags (:standard -w -8)))\n' > "$role/dune"
expect 0 "$role_cmt" ox-warning-policy direct; expect 0 "$role_cmti" ox-warning-policy direct
# Excluding the inspected module with the same expression must invalidate old ownership.
printf '(library (name foo) (wrapped false) (modules (:standard \\ member other)))\n(library (name bar) (wrapped false) (modules member other) (flags (:standard -w -8)))\n' > "$role/dune"
expect 2 "$role_cmt" ox-warning-policy direct; expect 2 "$role_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# Even a matching old owner cannot prove an ambiguous or unresolved current assignment.
ORACLE_CASE=owner
printf '(library (name foo) (wrapped false) (modules member spare))\n(library (name bar) (wrapped false) (modules member other))\n' > "$role/dune"
expect 2 "$role_cmt" ox-warning-policy direct; expect 2 "$role_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(library (name foo) (wrapped false) (modules member spare))\n(library (name bar) (wrapped false) (modules (:include modules.sexp)))\n' > "$role/dune"
printf '(other)\n' > "$role/modules.sexp"
ORACLE_CASE=unresolved
expect 2 "$role_cmt" ox-warning-policy direct; expect 2 "$role_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# A unique default owner is supported, not rejected merely for omitting modules.
printf '(library (name foo) (wrapped false))\n' > "$role/dune"
expect 0 "$role_cmt" ox-warning-policy direct; expect 0 "$role_cmti" ox-warning-policy direct
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
expect 0 "$sharing_cmt" ox-warning-policy direct; expect 0 "$sharing_cmti" ox-warning-policy direct
expect 0 "$sharing_second_cmt" ox-warning-policy direct; expect 0 "$sharing_second_cmti" ox-warning-policy direct
# A different sharing name is not disjoint: its weaker guard must be rejected.
ORACLE_CASE=sharing-weak
printf '(test (name first) (modules first helper))\n(test (name second) (modules second helper) (flags (:standard -w -8)))\n' > "$sharing/dune"
expect 2 "$sharing_cmt" ox-warning-policy direct; expect 2 "$sharing_cmti" ox-warning-policy direct
grep -q 'disagrees with recorded compiler warning settings' "$scratch/output"
# Unknown/default overlap cannot borrow the finite explicit-sharing proof.
printf '(test (name first) (modules first helper))\n(test (name second) (modules (:include modules.sexp)))\n' > "$sharing/dune"
printf '(second helper)\n' > "$sharing/modules.sexp"
ORACLE_CASE=unresolved
expect 2 "$sharing_cmt" ox-warning-policy direct; expect 2 "$sharing_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(test (name second))\n' > "$sharing/dune"
ORACLE_CASE=owner
expect 2 "$sharing_cmt" ox-warning-policy direct; expect 2 "$sharing_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
# Sharing does not repair exclusion from the exact recorded role or duplicate owners.
printf '(test (name first) (modules first))\n(test (name second) (modules second helper))\n' > "$sharing/dune"
expect 2 "$sharing_cmt" ox-warning-policy direct; expect 2 "$sharing_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(test (name first) (modules second helper))\n' > "$sharing/dune"
expect 2 "$sharing_cmt" ox-warning-policy direct; expect 2 "$sharing_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(tests (names second second) (modules second helper))\n' > "$sharing/dune"
expect 2 "$sharing_cmt" ox-warning-policy direct; expect 2 "$sharing_cmti" ox-warning-policy direct
grep -q 'unverified Dune source ownership' "$scratch/output"
printf '(test (name first) (modules first helper))\n(test (name second) (modules second helper))\n' > "$sharing/dune"
expect 0 "$sharing_cmt" ox-warning-policy direct; expect 0 "$sharing_cmti" ox-warning-policy direct
[[ "$(sha256sum "$sharing/helper.ml" "$sharing/helper.mli" "$sharing_cmt" "$sharing_cmti")" = "$sharing_hash" ]]
[[ "$(stat -c '%n:%y' "$sharing/helper.ml" "$sharing/helper.mli" "$sharing_cmt" "$sharing_cmti")" = "$sharing_time" ]]
check_source_control() { ORACLE_CASE=$3; expect "$1" "$2"; }
SOURCE_FIXTURES="$SCRIPT_DIR/negative"
source "$SCRIPT_DIR/source_controls.sh"
check_annotation() { ORACLE_CASE=${3:-owner}; expect "$1" "$2" ox-warning-policy direct; }
source "$SCRIPT_DIR/reorder.sh"
echo 'registered warning policy: files, load paths, current ownership, shared-role guards, freshness and language standards verified'
