#!/usr/bin/env bash
# ^nonce-ldtz ^nonce-r7mi ^nonce-4jzx ^nonce-nngp ^nonce-lrzq ^nonce-mjpe:
# Installed public consumer proof, separate from provider-annotation validation.
# Run: nix develop -c bash test/core/safety_once_global/check-installed.sh
# KEEP_INSTALLED_ONCE_PROOF=1 retains the external prefix, sources and diagnostics.
set -euo pipefail
root=$(realpath "$(dirname "$0")/../../..")
fixtures="$root/test/core/safety_once_global"
scratch=$(realpath "$(mktemp -d /var/tmp/ox-once-global-installed.XXXXXX)")
case "$scratch" in /var/tmp/ox-once-global-installed.*) ;; *) exit 2 ;; esac
inside_scratch() {
  case "$(realpath -m "$1")" in "$scratch"|"$scratch"/*) ;; *) printf 'unsafe proof path: %s\n' "$1" >&2; exit 2 ;; esac
}
cleanup() {
  rc=$?
  trap - EXIT
  inside_scratch "$scratch"
  if [[ $rc != 0 || ${KEEP_INSTALLED_ONCE_PROOF:-0} == 1 ]]; then
    printf 'external proof artifacts retained: %s\n' "$scratch" >&2
  else
    rm -rf -- "${scratch:?}"
  fi
  exit "$rc"
}
trap cleanup EXIT
# Neither the prefix nor consumer may inherit a Git checkout through an ancestor.
python3 - "$scratch" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]).resolve()
for ancestor in (p, *p.parents):
    if (ancestor / '.git').exists() or (ancestor / '.git').is_symlink():
        raise SystemExit(f'external proof has a Git ancestor: {ancestor}')
PY
prefix="$scratch/prefix"
consumer="$scratch/consumer"
mkdir -p "$consumer/fixtures"
# Pin the audited bytes before installation; never rewrite the provider to suit this test.
check_pins() {
  [[ $(md5sum "$1/once.ml" | cut -d ' ' -f1) == fe73e6eb236332ccc1f08748ddf88c31 ]]
  [[ $(md5sum "$1/once.mli" | cut -d ' ' -f1) == d4fddfdf736cf8ec1cb7e9ba2eac2a70 ]]
}
check_pins "$root/lib/ox"
cp "$fixtures/once_runtime.ml" "$fixtures/once_runtime.mli" "$consumer/"
cp "$fixtures"/compile_fail/good_*.ml "$fixtures"/compile_fail/bad_*.ml "$fixtures"/compile_fail/good_*.mli "$fixtures"/compile_fail/bad_*.mli "$consumer/fixtures/"
# Actual installation, not copies of the checkout's private object directories.
(cd "$root"; dune build @install; dune install --prefix "$prefix" --libdir "$prefix/lib" ox ox_caps ox_lint ox_test) >"$scratch/install.out" 2>"$scratch/install.err"
check_pins "$prefix/lib/ox"
python3 - "$prefix" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]).resolve()
for entry in p.rglob('*'):
    if entry.is_symlink() and not entry.resolve().is_relative_to(p):
        raise SystemExit(f'installed entry escapes prefix: {entry}')
PY
# From here every compile, execution and lint scan runs outside the checkout.
cd "$consumer"
unset INSIDE_DUNE DUNE_BUILD_DIR DUNE_WORKSPACE_ROOT
export OCAMLPATH="$prefix/lib"
[[ $(ocamlc -version) == 5.4.0+ox ]]
[[ $(realpath "$(ocamlfind query ox)") == "$prefix/lib/ox" ]]
[[ $(realpath "$(ocamlfind query ox_caps)") == "$prefix/lib/ox_caps" ]]
ocamlfind query -recursive ox eio.mock alcotest >"$scratch/resolved-packages.txt"
if grep -Fq "$root" "$scratch/resolved-packages.txt"; then
  printf 'package resolution borrowed the checkout\n' >&2; exit 1
fi
compiler=$(command -v ocamlc)
compile_fixture() {
  (cd "$consumer/fixtures";
    peer="${1%.ml}.mli"
    if [[ -f $peer ]]; then
      ocamlfind ocamlc -package ox -c "$peer" || exit 97
    else
      printf 'missing authored installed interface: %s\n' "$peer" >&2
      exit 97
    fi
    ocamlfind ocamlc -package ox -c "$1") >"$scratch/compile.out" 2>&1
}
positive=0
negative=0
for source in "$consumer"/fixtures/good_*.ml; do
  if ! compile_fixture "${source##*/}"; then
    printf 'installed positive fixture failed: %s\n' "${source##*/}" >&2
    sed -n '1,100p' "$scratch/compile.out" >&2
    exit 1
  fi
  positive=$((positive + 1))
done
for source in "$consumer"/fixtures/bad_*.ml; do
  expected='unique|aliased|once|many|local|global|escapes'
  [[ ${source##*/} != bad_guard_type.ml ]] || expected='unit ->'
  rc=0
  compile_fixture "${source##*/}" || rc=$?
  if [[ $rc == 97 ]]; then
    printf 'authored installed interface failed before implementation: %s\n' "${source##*/}" >&2
    sed -n '1,100p' "$scratch/compile.out" >&2
    exit 1
  fi
  if [[ $rc == 0 ]]; then
    printf 'installed negative fixture compiled: %s\n' "${source##*/}" >&2; exit 1
  fi
  if [[ $rc != 2 ]]; then
    printf 'installed negative expected native compiler status 2, got %s: %s\n' "$rc" "${source##*/}" >&2
    sed -n '1,100p' "$scratch/compile.out" >&2
    exit 1
  fi
  # Exclude echoed source: the compiler's diagnostic must identify the mode/type error.
  if ! sed -n '/^Error:/,$p' "$scratch/compile.out" | grep -Eq "$expected"; then
    printf 'wrong installed negative diagnostic: %s\n' "${source##*/}" >&2
    sed -n '1,100p' "$scratch/compile.out" >&2
    exit 1
  fi
  negative=$((negative + 1))
done
[[ $positive == 14 && $negative == 19 ]]
# The unchanged public runtime suite includes reuse/drop, defects, 16-domain contention,
# cancellation, release hooks, fork cleanup, concurrent mapper reuse and limiter paths.
ocamlfind ocamlopt -package ox,eio.mock,alcotest -bin-annot -c once_runtime.mli
ocamlfind ocamlopt -package ox,eio.mock,alcotest -bin-annot -c once_runtime.ml
ocamlfind ocamlopt -package ox,eio.mock,alcotest -linkpkg once_runtime.cmx -o once-runtime.exe
./once-runtime.exe >"$scratch/runtime.out" 2>"$scratch/runtime.err"
# The installed executable must still report ordinary unsafe casts in a consumer.
cat >bad_cast.ml <<'ML'
(* ^nonce-mjpe: an ordinary unchecked cast, never an approved Once implementation. *)
let cast (n : int) : string = Obj.magic n
external opaque_identity : int -> string = "%identity"
ML
printf '(** ^nonce-mjpe: authored installed negative source peer. *)\n' >bad_cast.mli
ocamlfind ocamlopt -package ox -bin-annot -c bad_cast.mli
ocamlfind ocamlopt -package ox -bin-annot -c bad_cast.ml
lint="$prefix/bin/ox-lint"
expect_lint() {
  expected=$1
  label=$2
  shift 2
  actual=0
  "$lint" --require-typed --rules ox-obj-magic --rules ox-identity-external "$@" >"$scratch/$label.out" 2>"$scratch/$label.err" || actual=$?
  if [[ $actual != "$expected" ]]; then
    printf '%s: wanted lint exit %s, got %s\n' "$label" "$expected" "$actual" >&2
    sed -n '1,100p' "$scratch/$label.out" "$scratch/$label.err" >&2
    exit 1
  fi
}
expect_lint 0 consumer-clean "$consumer/once_runtime.ml"
expect_lint 1 consumer-bad-cast "$consumer/bad_cast.ml"
grep -Fq 'ox-obj-magic:' "$scratch/consumer-bad-cast.out"
grep -Fq 'ox-identity-external:' "$scratch/consumer-bad-cast.out"
printf 'installed PUBLIC CONSUMER: %s positives / %s negatives; 9 global guard/direct-local wrapper tests; clean caller / bad cast and identity findings: pass\n' "$positive" "$negative"
# Separate provider proof: baseline must pass on genuine installed bytes.
# No rebasing-unsupported result is accepted as provider validation.
provider="$prefix/lib/ox/ox__Once.cmt"
peer="$prefix/lib/ox/ox__Once.cmti"
[[ -f $provider && -f $peer && -f $prefix/lib/ox/ox__Once.cmi ]]
ocamlobjinfo "$provider" >"$scratch/provider-objinfo.txt"
# An absolute checkout builddir could silently borrow private evidence. Do not scan it.
if grep -Fq "$root" "$scratch/provider-objinfo.txt"; then
  printf 'provider annotation contains checkout paths; refusing a checkout fallback\n' >&2
  exit 1
fi
provider_hashes=$(md5sum "$provider" "$peer" "$prefix/lib/ox/ox__Once.cmi")
cp -p "$peer" "$scratch/audited-once.cmti"
expect_lint 0 provider-clean "$provider"
inside_scratch "$peer"
inside_scratch "$peer.missing"
mv -- "$peer" "$peer.missing"
expect_lint 2 provider-missing-peer "$provider"
grep -Fq 'ox-obj-magic:' "$scratch/provider-missing-peer.out"
mv -- "$peer.missing" "$peer"
# A different installed interface is not a matching Once peer; restore audited bytes.
cp "$prefix/lib/ox/ox__Scope.cmti" "$peer"
expect_lint 2 provider-mismatched-peer "$provider"
grep -Fq 'ox-obj-magic:' "$scratch/provider-mismatched-peer.out"
cp -p "$scratch/audited-once.cmti" "$peer"
# Current public CMI is independently mandatory; interface bytes alone do not approve.
public_cmi="$prefix/lib/ox/ox__Once.cmi"
inside_scratch "$public_cmi"
inside_scratch "$public_cmi.missing"
cp -p "$public_cmi" "$scratch/audited-once.cmi"
mv -- "$public_cmi" "$public_cmi.missing"
expect_lint 2 provider-missing-public-cmi "$provider"
grep -Fq 'missing imported CMI Ox__Once' "$scratch/provider-missing-public-cmi.err"
mv -- "$public_cmi.missing" "$public_cmi"
cp "$prefix/lib/ox/ox__Scope.cmi" "$public_cmi"
expect_lint 2 provider-wrong-public-cmi-owner "$provider"
grep -Fq 'imported CMI fingerprint changed for Ox__Once' "$scratch/provider-wrong-public-cmi-owner.err"
grep -Fq 'wrong compilation unit' "$scratch/provider-wrong-public-cmi-owner.err"
cp -p "$scratch/audited-once.cmi" "$public_cmi"
expect_lint 0 provider-restored-public-contract "$provider"
[[ $(md5sum "$provider" "$peer" "$prefix/lib/ox/ox__Once.cmi") == "$provider_hashes" ]]
check_pins "$prefix/lib/ox"
printf 'installed PROVIDER CMT: genuine seven-line global guard clean; missing/mismatched peer and missing/wrong-owner public CMI strictly unknown; audited bytes restored: pass\n'
printf 'external consumer/prefix: %s; compiler: %s; no checkout/private object fallback\n' "$scratch" "$compiler"
