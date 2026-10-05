#!/usr/bin/env bash
set -euo pipefail
# ^safe-p9cw ^safe-8peq ^safe-5a9k: explicit installed-prefix native-clock evidence.
# Run manually under the source tree development environment; never registered in runtest.
# nix develop -c bash test/otel/safety_monotonic/prove-installed.sh /absolute/ox/worktree
source_root=${1:?usage: bash prove-installed.sh /absolute/ox/worktree [external-proof-directory]}
case "$source_root" in /*) ;; *) echo "absolute source root required" >&2; exit 2;; esac
proof_root=${2:-/var/tmp/ox-monotonic-installed-proof}
mkdir -p "$proof_root"
proof_root=$(realpath "$proof_root")
run=$(mktemp -d "$proof_root/run.XXXXXXXX")
for child in "$run" "$run/prefix" "$run/consumer"; do
  ancestor=$child
  while :; do
    test ! -e "$ancestor/.git" || { echo "Git ancestry: $ancestor" >&2; exit 3; }
    test "$ancestor" != / || break
    ancestor=$(dirname "$ancestor")
  done
done
cd "$run"
trap 'status=$?; printf "%s\n" "$status" > "$run/proof.exit"' EXIT
exec > >(tee "$run/proof.log") 2>&1
echo "PROOF_RUN=$run"
echo "GIT_ANCESTRY_ABSENT=1"
prefix=$run/prefix
consumer=$run/consumer
mkdir -p "$consumer/ws" "$consumer/otel"
packages=(ox_caps ox ox_blocking ox_json ox_http ox_observability ox_otel ox_test)
targets=()
for package in "${packages[@]}"; do targets+=("$package.install"); done
(cd "$source_root"; dune build "${targets[@]}"; dune install --prefix "$prefix" --sections lib "${packages[@]}")
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
for package in "${packages[@]}"; do
  origin=$(ocamlfind query "$package")
  case "$(readlink -f "$origin")" in "$prefix"/lib/*) ;; *) echo "not installed: $package=$origin" >&2; exit 4;; esac
  echo "INSTALLED_ORIGIN[$package]=$origin"
done
test ! -L "$prefix/lib/ox_http/ox_http.cmi"
test ! -L "$prefix/lib/ox_otel/ox_otel.cmi"
echo "GENUINE_PREFIX=1"
cp "$source_root/test/http/ws_client/safety_monotonic/"{positive.ml,positive.mli,wall.bad} "$consumer/ws/"
cp "$source_root/test/otel/safety_monotonic/"{positive.ml,positive.mli,wall.bad,calendar.bad} "$consumer/otel/"
cp "$source_root/test/http/ws_client/test_regressions.ml" "$consumer/ws/"
cp "$source_root/test/otel/ending.ml" "$consumer/otel/"
printf "%s
" "val cases : unit Alcotest.test_case list" > "$consumer/ws/test_regressions.mli"
printf "%s
" "(** Installed native-clock public witnesses. *)" > "$consumer/otel/ending.mli"
printf "%s
" "(** Installed native-clock public witnesses. *)" > "$consumer/ws/actual.mli"
printf "%s
" 'let () = Alcotest.run "installed native refill" ["actual", Test_regressions.cases]' > "$consumer/ws/actual.ml"
(cd "$consumer/ws"; echo "CONSUMER_CWD=$PWD"; ocamlfind ocamlopt -package ox_http,eio.mock -linkpkg positive.mli positive.ml -o positive.exe; ./positive.exe; echo WS_NATIVE_REFUSAL=1; ocamlfind ocamlopt -package ox_http,eio.mock,alcotest -linkpkg test_regressions.mli test_regressions.ml actual.mli actual.ml -o actual.exe; ./actual.exe)
(cd "$consumer/otel"; echo "CONSUMER_CWD=$PWD"; ocamlfind ocamlopt -package ox_otel,ox_test,eio.mock -linkpkg positive.mli positive.ml -o positive.exe; ./positive.exe; echo OTEL_NATIVE_REFUSAL=1; ocamlfind ocamlopt -package ox_otel,ox_test,eio.mock,eio_main,yojson,alcotest -linkpkg ending.mli ending.ml -o actual.exe; ./actual.exe)
negative() {
  directory=$1; name=$2; packages=$3
  cp "$directory/$name.bad" "$directory/negative.ml"
  set +e
  (cd "$directory"; ocamlfind ocamlc -package "$packages" -c negative.ml) > "$directory/$name.stderr" 2>&1
  status=$?
  set -e
  printf "%s
" "$status" > "$directory/$name.exit"
  echo "DIRECT_NEGATIVE_EXIT[$directory/$name]=$status"
  python3 - "$directory/$name.stderr" "$status" <<'PY'
import pathlib, sys
diagnostic = pathlib.Path(sys.argv[1]).read_text()
assert sys.argv[2] == "2", (sys.argv[2], diagnostic)
assert "Error:" in diagnostic and "float" in diagnostic and "Mtime.t" in diagnostic, diagnostic
assert "Types for tag `Clock are incompatible" in diagnostic, diagnostic
assert "Unbound" not in diagnostic and "Syntax error" not in diagnostic, diagnostic
print("EXPECTED_NATIVE_CLOCK_REJECTION=1")
PY
}
negative "$consumer/ws" wall ox_http,eio.mock
negative "$consumer/otel" wall ox_otel,ox_test,eio.mock
negative "$consumer/otel" calendar ox_otel,ox_test,eio.mock
sha256sum "$consumer/ws/"{positive.ml,positive.mli,wall.bad,test_regressions.ml} "$consumer/otel/"{positive.ml,positive.mli,wall.bad,calendar.bad,ending.ml}
printf "0
" > "$run/proof.exit"
echo "INSTALLED_MONOTONIC_PROOF_EXIT=0"
