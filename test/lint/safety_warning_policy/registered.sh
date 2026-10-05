#!/usr/bin/env bash
# ^safe-tpzm ^safe-zxc1: registered CLI regressions for real compiler ownership.
set -euo pipefail
BIN=$(realpath -e -- "${BIN:-${1:?registered candidate executable}}")
ROOT=$(realpath -e -- "${ROOT:-${2:?candidate evidence root}}")
[[ "$BIN" = /* && "$ROOT" = /* ]]
scratch=$(mktemp -d /var/tmp/ox-warning-registered.XXXXXXXX)
[[ "$scratch" = /var/tmp/ox-warning-registered.* && -d "$scratch" ]]
trap 'rm -rf -- "${scratch:?}"' EXIT
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
}
# A directory called dune is not a policy file, even in a source ancestor.
mkdir "$scratch/dune" "$scratch/standalone"
printf 'let value = 1\n' > "$scratch/standalone/value.ml"
(cd "$scratch/standalone"; ocamlc -bin-annot -warn-error +a -c value.ml)
expect 0 "$scratch/standalone/value.cmt"
(cd "$scratch/standalone"; ocamlc -bin-annot -warn-error -a -c value.ml)
expect 1 "$scratch/standalone/value.cmt"
# Dune executable implicit opens must survive warning attribute inspection.
mkdir "$scratch/executable"
printf '(lang dune 3.21)\n(name executable_scope)\n' > "$scratch/executable/dune-project"
printf '(executable (name main) (modules main support))\n' > "$scratch/executable/dune"
printf 'let value = 1\n' > "$scratch/executable/support.ml"
printf 'let () = ignore (Ok Support.value)\n' > "$scratch/executable/main.ml"
(cd "$scratch/executable"; dune build @check)
expect 1 "$scratch/executable/main.ml" all
grep -q 'ox-discarded-result:' "$scratch/output"
! grep -q 'Cannot find module\|unverified\|undecided' "$scratch/output"
printf 'let () = ignore (Ok (Support.value + 1))\n' > "$scratch/executable/main.ml"
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
expect 2 "$generated" ox-warning-policy direct
grep -q 'digest\|stale' "$scratch/output"
cp "$scratch/empty-interface" "$body"
printf '(executable (name main) (modules main support) (empty_module_interface false) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/executable/dune"
expect 2 "$generated" ox-warning-policy direct
grep -q 'generated empty interface producer/unit ownership' "$scratch/output"
printf '(executable (name main) (modules main support) (flags (:standard -w -8)) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/executable/dune"
expect 2 "$generated" ox-warning-policy direct
grep -q 'disagrees with recorded compiler warning settings' "$scratch/output"
(cd "$scratch/executable"; dune build @check)
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
expect 1 "$scratch/libraries/unrelated.ml"
# Direct compiler metadata cannot assert which Dune library owns it.
printf 'let value = 1\n' > "$scratch/libraries/unowned.ml"
(cd "$scratch/libraries"; ocamlc -bin-annot -warn-error +a -c unowned.ml)
expect 2 "$scratch/libraries/unowned.cmt"
grep -q 'no exact checked compiler scope' "$scratch/output"
# Verify the audited language transition without lowering root protection.
printf '(lang dune 3.22)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
(cd "$scratch/libraries"; dune build @check)
expect 0 "$scratch/libraries/selected.ml"
printf '(lang dune 3.20)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
(cd "$scratch/libraries"; dune build @check)
expect 1 "$scratch/libraries/selected.ml"
grep -q 'required active/fatal warnings disabled' "$scratch/output"
! grep -q 'unverified\|undecided' "$scratch/output"
printf '(library (name selected) (wrapped false) (modules selected) (flags (:standard -warn-error +a)))\n(library (name unrelated) (wrapped false) (modules unrelated) (flags (:standard -w -8)))\n' > "$scratch/libraries/dune"
(cd "$scratch/libraries"; dune build @check)
expect 0 "$scratch/libraries/selected.ml"
printf '(lang dune 3.23)\n(name library_scopes)\n' > "$scratch/libraries/dune-project"
expect 2 "$scratch/libraries/selected.ml"
grep -q 'unverified Dune language standard: 3.23' "$scratch/output"
echo 'registered warning policy: files, load paths, scopes, freshness and language standards verified'
