#!/usr/bin/env bash
# ^safe-y047 ^nlintcov-q6n2: genuine direct generation and exact failure locations/categories.
set -euo pipefail
probe=$(realpath "$1")
real_dune=$(command -v dune)
scratch=$(mktemp -d /var/tmp/ox-generated-interface.XXXXXXXX)
case "$scratch" in /var/tmp/ox-generated-interface.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "${scratch:?}"' EXIT
unset DUNE_INSIDE_DUNE
mkdir "$scratch/template"
printf '(lang dune 3.22)\n' > "$scratch/template/dune-project"
printf '(executables (names run other) (preprocess (action (run cat %%{input-file}))))\n' > "$scratch/template/dune"
printf 'let () = ()\n' > "$scratch/template/run.ml"
printf 'let () = ()\n' > "$scratch/template/other.ml"
mkdir "$scratch/template/evidence"
printf 'val unexpected : int\n' > "$scratch/template/evidence/dune__exe__Run.mli"
ocamlc -bin-annot -c -o "$scratch/template/evidence/dune__exe__Run.cmi" "$scratch/template/evidence/dune__exe__Run.mli"
dune build --root "$scratch/template" @check
copy_case() {
  cp -a "$scratch/template" "$scratch/$1"
  case_root="$scratch/$1"
  cmti="$case_root/_build/default/.run.eobjs/byte/dune__exe__Run.cmti"
  export CASE_ROOT="$case_root"
}
reject() {
  local location=$1 category=$2 diagnostic
  shift 2
  if diagnostic=$("$@" 2>&1); then echo "unexpected acceptance: $location ($category)" >&2; exit 1; fi
  if [[ $diagnostic != *"$location"* || $diagnostic != *"$category"* ]]; then
    printf 'wrong location/category; expected %s / %s; got %s\n' "$location" "$category" "$diagnostic" >&2
    exit 1
  fi
}
copy_case positive
"$probe" checked "$case_root" "$cmti" "$case_root/_build/default/.run.eobjs/byte/dune__exe__Other.cmti"
copy_case uncached
reject "$cmti" 'generated empty interface: inventory unavailable' "$probe" uncached "$case_root" "$cmti"
copy_case missing-digest
reject "$cmti" 'annotation has no source digest' "$probe" missing-digest "$case_root" "$cmti"
copy_case stale-digest
reject "$cmti" 'digest mismatch' "$probe" stale-digest "$case_root" "$cmti"
for scenario in missing-interface-digest missing-self-import; do
  copy_case "$scenario"
  reject "$cmti" 'required annotation self import missing or changed' "$probe" "$scenario" "$case_root" "$cmti"
done
for scenario in incomplete-signature nonempty-signature; do
  copy_case "$scenario"
  reject "$cmti" 'compiled signature is not empty' "$probe" "$scenario" "$case_root" "$cmti"
done
copy_case owner-changed
printf '%s\n' 'printf "\n; owner changed\n" >> "$CASE_ROOT/dune"' > "$scratch/change.sh"
reject "$cmti" 'configuration changed since inventory' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
for scenario in owner-deleted owner-renamed; do
  copy_case "$scenario"
  printf '%s\n' 'mv "$CASE_ROOT/run.ml" "$CASE_ROOT/run.ml.hidden"' > "$scratch/change.sh"
  if [[ $scenario == owner-deleted ]]; then
    printf '%s\n' 'rm -- "$CASE_ROOT/run.ml.hidden"' >> "$scratch/change.sh"
  fi
  reject "$cmti" 'configuration changed since inventory' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
done
# Both the include entry and a symlink in its parent path retain lexical identity.
# Old targets remain completely untouched; new targets deliberately have identical bytes.
for scenario in include-retarget include-parent-retarget; do
  copy_case "$scenario"
  mkdir "$case_root/a" "$case_root/b"
  printf '(env (_ (flags :standard)))\n' > "$case_root/a/owner.dune"
  cp -p "$case_root/a/owner.dune" "$case_root/b/owner.dune"
  if [[ $scenario == include-retarget ]]; then
    ln -s a/owner.dune "$case_root/owner.dune"
    printf '(include owner.dune)\n' >> "$case_root/dune"
    printf '%s\n' 'ln -s b/owner.dune "$CASE_ROOT/new-link"; mv -Tf "$CASE_ROOT/new-link" "$CASE_ROOT/owner.dune"' > "$scratch/change.sh"
  else
    ln -s a "$case_root/owner"
    printf '(include owner/owner.dune)\n' >> "$case_root/dune"
    printf '%s\n' 'ln -s b "$CASE_ROOT/new-link"; mv -Tf "$CASE_ROOT/new-link" "$CASE_ROOT/owner"' > "$scratch/change.sh"
  fi
  "$probe" checked "$case_root" "$cmti"
  reject "$cmti" 'configuration changed since inventory' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
done
copy_case root-config-changed
printf '%s\n' 'printf "(env (_ (flags (:standard -w +a))))\n" > "$CASE_ROOT/dune-workspace"' > "$scratch/change.sh"
reject "$cmti" 'configuration changed since inventory' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case order-changed
export SAVED_OBJECTS="$scratch/order-objects"
cp -a "$case_root/_build/default/.run.eobjs" "$SAVED_OBJECTS"
sed -i 's/names run other/names other run/' "$case_root/dune"
# Dune removes obsolete targets during describe; restore a genuine stale object group.
printf '%s\n' 'mkdir -p "$CASE_ROOT/_build/default/.run.eobjs"' 'cp -a "$SAVED_OBJECTS/." "$CASE_ROOT/_build/default/.run.eobjs/"' > "$scratch/change.sh"
reject "$cmti" 'compiler owner mismatch' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case input-changed
printf '%s\n' 'printf "\000binary fake AST" > "$CASE_ROOT/_build/default/input-mutation"; mv "$CASE_ROOT/_build/default/input-mutation" "$CASE_ROOT/_build/default/run.pp.mli"' > "$scratch/change.sh"
reject "$cmti" 'compiler input is not the direct empty output' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case authored-appeared
printf '%s\n' 'printf "[@@@ox.domain]\n" > "$CASE_ROOT/run.mli"' > "$scratch/change.sh"
reject "$cmti" 'original interface now exists' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case intermediate-appeared
printf '%s\n' 'printf "(* Auto-generated by Dune *)" > "$CASE_ROOT/_build/default/run.mli"' > "$scratch/change.sh"
reject "$cmti" 'original interface now exists' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case wrong-annotation
printf '%s\n' 'cp "$CASE_ROOT/_build/default/.run.eobjs/byte/dune__exe__Other.cmti" "$CASE_ROOT/_build/default/.run.eobjs/byte/annotation-mutation"; mv "$CASE_ROOT/_build/default/.run.eobjs/byte/annotation-mutation" "$CASE_ROOT/_build/default/.run.eobjs/byte/dune__exe__Run.cmti"' > "$scratch/change.sh"
reject "$cmti" 'annotation compilation unit differs from its object name' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case wrong-cmi
printf '%s\n' 'cp "$CASE_ROOT/_build/default/.run.eobjs/byte/dune__exe__Other.cmi" "$CASE_ROOT/_build/default/.run.eobjs/byte/cmi-mutation"; mv "$CASE_ROOT/_build/default/.run.eobjs/byte/cmi-mutation" "$CASE_ROOT/_build/default/.run.eobjs/byte/dune__exe__Run.cmi"' > "$scratch/change.sh"
reject "$cmti" 'imported CMI fingerprint changed for Dune__exe__Run' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
copy_case stale-cmi
printf '%s\n' 'cp "$CASE_ROOT/evidence/dune__exe__Run.cmi" "$CASE_ROOT/_build/default/.run.eobjs/byte/cmi-mutation"; mv "$CASE_ROOT/_build/default/.run.eobjs/byte/cmi-mutation" "$CASE_ROOT/_build/default/.run.eobjs/byte/dune__exe__Run.cmi"' > "$scratch/change.sh"
reject "$cmti" 'imported CMI fingerprint changed for Dune__exe__Run' "$probe" after "$case_root" "$scratch/change.sh" "$cmti"
# Inject adversarial inventory responses only; the source/annotations remain genuine.
mkdir "$scratch/bin"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'if [[ "$1 $2" == "describe rules" ]]; then' \
  '  case "$MOCK_RULES" in' \
  '    absent) exit 0 ;;' \
  '    unavailable) exit 1 ;;' \
  '    duplicate) "$REAL_DUNE" "$@"; "$REAL_DUNE" "$@"; exit ;;' \
  '    producer) "$REAL_DUNE" "$@" | sed "s/Auto-generated by Dune/Not-generated by Dune/g"; exit ;;' \
  '    compiler) "$REAL_DUNE" "$@" | sed "s/dune__exe__Run.cmti/dune__exe__Wrong.cmti/g"; exit ;;' \
  '  esac' \
  'fi' \
  'exec "$REAL_DUNE" "$@"' > "$scratch/bin/dune"
chmod +x "$scratch/bin/dune"
for scenario in absent duplicate producer compiler; do
  copy_case "rules-$scenario"
  reject "$cmti" 'missing or ambiguous direct producer/compiler owner' \
    env REAL_DUNE="$real_dune" MOCK_RULES="$scenario" PATH="$scratch/bin:$PATH" \
    "$probe" checked "$case_root" "$cmti"
done
copy_case rules-unavailable
reject "$case_root" 'Dune generated-source inventory unavailable' \
  env REAL_DUNE="$real_dune" MOCK_RULES=unavailable PATH="$scratch/bin:$PATH" \
  "$probe" checked "$case_root" "$cmti"
# A genuine compiler PPX erases the attribute from the marshalled AST, not text.
mkdir "$scratch/ppx-tool"
printf '%s\n' 'open Ast_mapper' 'open Parsetree' \
  'let () = run_main (fun _ -> { default_mapper with signature = (fun self items ->' \
  '  let mapped = default_mapper.signature self items in' \
  '  { mapped with psg_items = List.filter (fun item -> match item.psig_desc with' \
  '  | Psig_attribute a when a.attr_name.txt = "ox.domain" -> false | _ -> true) mapped.psg_items }) })' \
  > "$scratch/ppx-tool/erase.ml"
printf '' > "$scratch/ppx-tool/erase.mli"
ocamlc -c -o "$scratch/ppx-tool/erase.cmi" "$scratch/ppx-tool/erase.mli"
ocamlc -I +compiler-libs -I "$scratch/ppx-tool" ocamlcommon.cma "$scratch/ppx-tool/erase.ml" -o "$scratch/ppx-tool/erase.exe"
mkdir "$scratch/authored"
cp "$scratch/ppx-tool/erase.exe" "$scratch/authored/erase.exe"
printf '(lang dune 3.22)\n' > "$scratch/authored/dune-project"
printf '%s\n' '(executable (name run) (flags (:standard -ppx "./%{dep:erase.exe}")))' > "$scratch/authored/dune"
printf 'let () = ()\n' > "$scratch/authored/run.ml"
printf '[@@@ox.domain]\n' > "$scratch/authored/run.mli"
dune build --root "$scratch/authored" @check
"$probe" authored "$scratch/authored" "$scratch/authored/_build/default/.run.eobjs/byte/dune__exe__Run.cmti"
printf '%s\n' 'generated interfaces: physical inputs, exact owners, freshness, CMI and marker obligations: pass'
