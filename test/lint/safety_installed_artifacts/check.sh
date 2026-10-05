#!/usr/bin/env bash
# ^safe-y047 ^nlintcov-q6n2: genuine dune install, relocation, and fail-closed controls.
set -euo pipefail
probe=$(realpath "$1")
scratch=$(mktemp -d /var/tmp/ox-installed-artifacts.XXXXXXXX)
case "$scratch" in /var/tmp/ox-installed-artifacts.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "${scratch:?}"' EXIT
unset DUNE_INSIDE_DUNE
mkdir "$scratch/project"
printf '(lang dune 3.22)\n(package (name fixture))\n' > "$scratch/project/dune-project"
printf '(library (name fixture) (public_name fixture) (libraries fixture.helper))\n' > "$scratch/project/dune"
mkdir "$scratch/project/helper"
printf '(library (name fixture_helper) (public_name fixture.helper))\n' > "$scratch/project/helper/dune"
printf 'let answer = 1\n' > "$scratch/project/helper/fixture_helper.ml"
printf 'val answer : int\n' > "$scratch/project/helper/fixture_helper.mli"
printf 'let value = Fixture_helper.answer\n' > "$scratch/project/value.ml"
printf 'val value : int\n' > "$scratch/project/value.mli"
mkdir "$scratch/project/transformed"
printf '(library (name transformed) (public_name fixture.transformed) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/project/transformed/dune"
printf 'let answer = 1\n' > "$scratch/project/transformed/transformed.ml"
printf 'val answer : int\n' > "$scratch/project/transformed/transformed.mli"
dune build --root "$scratch/project" @install
dune install --root "$scratch/project" --prefix "$scratch/prefix"
cp -a "$scratch/prefix" "$scratch/relocated"
# Verify before touching the originals: this is a physical installation, not _build/install.
lib="$scratch/relocated/lib/fixture"
"$probe" "$lib/fixture__Value.cmt" "$lib/fixture__Value.cmti"
# Remove access to the old source/build/prefix; no fallback may rescue a bad installation.
mv "$scratch/project" "$scratch/project-hidden"
mv "$scratch/prefix" "$scratch/prefix-hidden"
"$probe" "$lib/fixture__Value.cmt" "$lib/fixture__Value.cmti"
reject() {
  local diagnostic
  if diagnostic=$("$probe" "$1" 2>&1); then
    echo "invalid installed evidence accepted: $1" >&2; exit 1
  fi
  if [[ $# == 2 && $diagnostic != *"$2"* ]]; then
    printf 'unexpected evidence failure: %s\n' "$diagnostic" >&2; exit 1
  fi
}

# ^safe-fr73: compile the SAME source under another unit, then misname its evidence.
# Both source digests remain genuine; wrong-source rejection cannot pass this control.
mkdir "$scratch/native"
printf 'val answer : int\n' > "$scratch/native/execution_context.mli"
printf 'let answer = 1\n' > "$scratch/native/execution_context.ml"
(
  cd "$scratch/native"
  ocamlopt -bin-annot -c execution_context.mli
  ocamlopt -bin-annot -c execution_context.ml
  "$probe" --unit-names execution_context.cmt execution_context.cmti
  ocamlopt -bin-annot -c -o wrong_unit.cmi -intf execution_context.mli
  ocamlopt -bin-annot -c -o wrong_unit.cmx -impl execution_context.ml
  mkdir renamed
  cp wrong_unit.cmt renamed/execution_context.cmt
  cp wrong_unit.cmti renamed/execution_context.cmti
  for annotation in renamed/execution_context.{cmt,cmti}; do
    if "$probe" --unit-names "$annotation" > "$scratch/unit-rejection.log" 2>&1; then
      echo "wrong compiler unit accepted: $annotation" >&2; exit 1
    fi
    if [[ $(< "$scratch/unit-rejection.log") != *"compilation unit differs"* ]]; then
      echo "wrong compiler unit rejected for another reason" >&2; exit 1
    fi
  done
)

copy_case() { cp -a "$scratch/relocated" "$scratch/$1"; case_lib="$scratch/$1/lib/fixture"; }
copy_case no-manifest
mv "$case_lib/dune-package" "$case_lib/manifest-hidden"
reject "$case_lib/fixture__Value.cmt"
mkdir "$scratch/checkout"
cp -a "$scratch/project-hidden/." "$scratch/checkout/"
cp -a "$scratch/relocated" "$scratch/checkout/installed"
mv "$scratch/checkout/installed/lib/fixture/dune-package" "$scratch/checkout/manifest-hidden"
reject "$scratch/checkout/installed/lib/fixture/fixture__Value.cmt" 'no manifest ownership outside the build tree'
copy_case ambiguous
# A duplicated module record must not be accepted by first-match selection.
sed -i '/(obj_name fixture__Value)/a\      (obj_name fixture__Value)' "$case_lib/dune-package"
reject "$case_lib/fixture__Value.cmt"
copy_case missing-sibling
mv "$case_lib/helper/fixture_helper.cmt" "$case_lib/helper/sibling-hidden"
reject "$case_lib/fixture__Value.cmt"
copy_case ambiguous-sibling
sed -i '/(obj_name fixture_helper)/a\      (obj_name fixture_helper)' "$case_lib/dune-package"
reject "$case_lib/fixture__Value.cmt"
copy_case duplicate-module
printf '%s
' '(library (modules (singleton (obj_name fixture__Value) (visibility public) (source (path Value) (impl (path value.ml))))))' >> "$case_lib/dune-package"
reject "$case_lib/fixture__Value.cmt"
copy_case cross-package
mv "$case_lib/helper" "$scratch/foreign-helper"
mkdir "$case_lib/helper"
# Another directory with valid provider artifacts cannot rescue the absent owner.
(cd "$scratch/foreign-helper"; reject "$case_lib/fixture__Value.cmt")
copy_case cwd-only
mkdir "$scratch/cwd-only-import"
mv "$case_lib/helper/fixture_helper.cmi" "$scratch/cwd-only-import/fixture_helper.cmi"
(cd "$scratch/cwd-only-import"; reject "$case_lib/fixture__Value.cmt")
copy_case cwd-poison
mkdir "$scratch/poison"
cp "$case_lib/helper/fixture_helper.cmi" "$scratch/poison/fixture.cmi"
(cd "$scratch/poison"; "$probe" "$case_lib/fixture__Value.cmt")
# A correct CMI in cwd must not rescue the wrong CMI at its manifest-owned path.
cp "$case_lib/fixture.cmi" "$scratch/poison/fixture.cmi"
cp "$case_lib/helper/fixture_helper.cmi" "$case_lib/fixture.cmi"
(cd "$scratch/poison"; reject "$case_lib/fixture__Value.cmt")
copy_case ppx
reject "$case_lib/transformed/transformed.cmt"
copy_case source
printf 'let value = 2\n' > "$case_lib/value.ml"
reject "$case_lib/fixture__Value.cmt"
copy_case interface
printf 'val value : string\n' > "$case_lib/value.mli"
reject "$case_lib/fixture__Value.cmti"
copy_case own-cmi
cp "$case_lib/fixture.cmi" "$case_lib/fixture__Value.cmi"
reject "$case_lib/fixture__Value.cmt"
copy_case wrapper-cmi
cp "$case_lib/fixture__Value.cmi" "$case_lib/fixture.cmi"
reject "$case_lib/fixture__Value.cmt"
copy_case wrong-crc
mkdir "$scratch/wrong-crc-source"
printf 'val changed : bool\n' > "$scratch/wrong-crc-source/fixture.mli"
ocamlc -c -o "$case_lib/fixture.cmi" "$scratch/wrong-crc-source/fixture.mli"
reject "$case_lib/fixture__Value.cmt" 'fingerprint changed for Fixture'
copy_case missing-peer
mv "$case_lib/fixture__Value.cmti" "$case_lib/peer-hidden"
reject "$case_lib/fixture__Value.cmti"
copy_case escaping
sed -i 's/(path value.ml)/(path ..\/..\/value.ml)/' "$case_lib/dune-package"
reject "$case_lib/fixture__Value.cmt"
copy_case symlink
mv "$case_lib/value.ml" "$scratch/escaped-value.ml"
ln -s "$scratch/escaped-value.ml" "$case_lib/value.ml"
reject "$case_lib/fixture__Value.cmt"
printf '%s\n' 'installed artifacts: relocation, ownership, sources, imports and peer controls: pass'
