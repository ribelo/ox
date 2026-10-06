#!/usr/bin/env bash
# Fresh native, MI-first and installed CLI checks for direct wall-clock misuse.
set -euo pipefail
driver=$(realpath -e "$1")
engine=$(realpath -e "$2")
evidence=$(realpath -e "$3")
clean=$(realpath -e "$4")
wall=$(realpath -e "$5")
prefix=$(realpath -e "$6")
work=$(mktemp -d /var/tmp/ox-monotonic-native.XXXXXX)
case "$work" in /var/tmp/ox-monotonic-native.*) ;; *) exit 1 ;; esac
inside() { [[ $(realpath -m "$1") == "$work/"* ]]; }
cleanup() { inside "$work/project" && rm -rf -- "$work"; }
trap cleanup EXIT
unset DUNE_INSIDE_DUNE
mkdir "$work/project"
cp "$evidence/dune" "$evidence/dune-project" "$evidence/.ocamlformat" "$work/project/"
cp "$evidence/unknown.ml" "$evidence/unknown.mli" "$work/project/"
cp "$clean/monotonic_elapsed_time.ml" "$work/project/clean.ml"
cp "$clean/monotonic_elapsed_time.mli" "$work/project/clean.mli"
cp "$wall/monotonic_elapsed_time.ml" "$work/project/wall.ml"
cp "$wall/monotonic_elapsed_time.mli" "$work/project/wall.mli"
cp "$engine" "$work/project/ox-lint"
chmod u+w "$work/project/dune"
printf '\n(install (package ox_lint) (section bin) (files ox-lint))\n' >> "$work/project/dune"
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
# Native compiler annotations, not Dune's byte-annotation convenience outputs.
# All three interfaces exist before any implementation is compiled.
packages=ox_caps,eio,mtime,unix
hidden=()
for package in ox_caps; do
  if test -d "$prefix/lib/$package/.private"; then
    hidden+=(-H "$prefix/lib/$package/.private")
  fi
done
cd "$work/project"
for name in wall clean unknown; do
  ocamlfind ocamlopt -package "$packages" "${hidden[@]}" -opaque -bin-annot -I . -c "$name.mli" -o "$name.cmi"
done
for name in wall clean unknown; do
  test -f "$name.cmti"
  test ! -e "$name.cmx"
  test ! -e "$name.cmo"
done
for name in wall clean unknown; do
  ocamlfind ocamlopt -package "$packages" "${hidden[@]}" -opaque -bin-annot -I . -c "$name.ml" -o "$name.cmx"
  test -f "$name.cmx"
  test -f "$name.cmt"
  test ! -e "$name.cmo"
done
ocamlopt -a -o monotonic_native.cmxa wall.cmx clean.cmx unknown.cmx
"$driver" "$work/project"
# Dune stages the real native library and engine for its genuine installer.
# @install also requests byte CMT convenience outputs. Replace annotations only
# with native compiler evidence after asserting byte-identical native CMIs.
dune build --root "$work/project" @install
for name in wall clean unknown; do
  cmp "$name.cmi" "_build/default/.monotonic_fixtures.objs/byte/$name.cmi"
  chmod u+w "_build/default/.monotonic_fixtures.objs/byte/$name.cmt" "_build/default/.monotonic_fixtures.objs/byte/$name.cmti"
  cp "$name.cmt" "_build/default/.monotonic_fixtures.objs/byte/$name.cmt"
  cp "$name.cmti" "_build/default/.monotonic_fixtures.objs/byte/$name.cmti"
done
# A real Dune installation, physical relocation and no remaining consumer build.
dune install --root "$work/project" --prefix "$work/installed"
cp -a "$work/installed" "$work/relocated"
cp "$work/installed/lib/monotonic_probe/clean.ml" "$work/clean.ml.saved"
inside "$work/project" && inside "$work/installed" && rm -rf -- "$work/project" "$work/installed"
cd "$work"
cli="$work/relocated/bin/ox-lint"
package="$work/relocated/lib/monotonic_probe"
expect() {
  local code=$1 name=$2 source=$3
  set +e
  "$cli" --root "$work/relocated" --rules ox-monotonic-elapsed-time --require-typed "$source" > "$work/$name.out" 2>&1
  local actual=$?
  set -e
  if [[ $actual != "$code" ]]; then
    printf 'installed %s: expected exit %s, got %s\n' "$name" "$code" "$actual" >&2
    python3 -c 'import sys; print(open(sys.argv[1]).read())' "$work/$name.out" >&2
    exit 1
  fi
}
expect 0 clean "$package/clean.ml"
expect 1 wall "$package/wall.ml"
expect 2 unknown "$package/unknown.ml"
python3 - "$work/wall.out" "$package/wall.ml" <<'PY'
import re, sys
lines = [int(m.group(1)) for m in re.finditer(re.escape(sys.argv[2]) + r':(\d+): ox-monotonic-elapsed-time:', open(sys.argv[1]).read())]
assert sorted(lines) == [3,7,9,12,16], lines
PY
printf '\n(* changed installed source *)\n' >> "$package/clean.ml"
expect 2 stale "$package/clean.ml"
inside "$package/clean.ml" && cp "$work/clean.ml.saved" "$package/clean.ml"
inside "$package/clean.cmi" && mv "$package/clean.cmi" "$package/clean.cmi.saved"
expect 2 missing_import "$package/clean.ml"
inside "$package/clean.cmi.saved" && mv "$package/clean.cmi.saved" "$package/clean.cmi"
expect 0 restored "$package/clean.ml"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
unknown = (root / 'unknown.out').read_text()
assert 'ox-monotonic-elapsed-time' in unknown and 'opaque wall-clock value' in unknown, unknown
stale = (root / 'stale.out').read_text()
assert 'stale typed annotation' in stale and 'digest mismatch' in stale, stale
missing = (root / 'missing_import.out').read_text().lower()
assert 'cmi' in missing and any(word in missing for word in ('missing', 'absent', 'not found', 'unavailable', 'no such file')), missing
PY
printf 'monotonic: fresh MI-first native exact-site oracle and relocated installed CLI passed\n'
