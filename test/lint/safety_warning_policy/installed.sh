#!/usr/bin/env bash
# ^safe-tpzm ^safe-zxc1: genuine installation and external compiled consumer seam.
set -euo pipefail
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
  "$BIN" --root "$SHARE" --require-typed --rules ox-warning-policy "$target" > "$output" 2>&1 || status=$?
  if [[ "$expected" = clean ]]; then
    [[ $status = 0 ]] || { sed -n '1,100p' "$output" >&2; exit 1; }
  elif [[ "$expected" = restriction ]]; then
    [[ $status != 0 ]] && grep -q 'ox-warning-policy' "$output" && grep -q 'required active/fatal warnings disabled' "$output" || { sed -n '1,100p' "$output" >&2; exit 1; }
  else
    [[ $status != 0 ]] && grep -q 'unverified\|undecided\|missing typed annotation' "$output" || { sed -n '1,100p' "$output" >&2; exit 1; }
  fi
}
run clean "$consumer/restored.ml"
run clean "$consumer/restored.mli"
run restriction "$consumer/bad.ml"
run restriction "$consumer/bad.mli"
# Opposing attached attributes are deliberately separate, not combined floating strings.
printf 'let value = 1 [@@warning "-8"] [@@warning "+8"]\n' > "$consumer/attached_bad.ml"
printf 'let value = 1 [@@warning "+8"] [@@warning "-8"]\n' > "$consumer/attached_clean.ml"
printf 'val value : int\n' > "$consumer/attached_bad.mli"
printf 'val value : int\n' > "$consumer/attached_clean.mli"
(cd "$consumer"; "$DUNE" build @check)
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
run unverified "$consumer/restored.ml"
# Concrete combined Dune restoration is certified from its own compiler command.
printf '(library (name consumer) (wrapped false) (flags (:standard -w -P)) (ocamlc_flags (-w +8)))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
run clean "$consumer/restored.ml"
# An unbuilt release scope cannot be certified by a dev artifact.
printf '(library (name consumer) (wrapped false))\n(env (release (flags (:standard -w -8))))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
run unverified "$consumer/restored.ml"
# Recorded compiler arguments do not resolve a current template content declaration.
printf '(library (name consumer) (wrapped false) (flags (:standard -w %%{env:WARNINGS=+a})))\n' > "$consumer/dune"
(cd "$consumer"; "$DUNE" build @check)
run unverified "$consumer/restored.ml"
printf '(library (name consumer) (wrapped false))\n' > "$consumer/dune"
# The compiled consumer remains external; invocation stays in the distinct cwd.
printf 'let value = 1\n' > "$consumer/missing.ml"
printf 'val value : int\n' > "$consumer/missing.mli"
run unverified "$consumer/missing.ml"
echo 'installed warning policy: compiled restrictions, restoration and unknown scopes verified'
