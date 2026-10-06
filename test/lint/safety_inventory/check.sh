#!/usr/bin/env bash
# ^safe-y047 ^nlintcov-q6n2: injected Dune responses cross the real Artifact boundary.
set -euo pipefail
probe=$(realpath "$1")
scratch=$(mktemp -d /var/tmp/ox-inventory.XXXXXXXX)
# Cleanup is confined to the absolute directory just returned by mktemp.
case "$scratch" in /var/tmp/ox-inventory.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir "$scratch/bin" "$scratch/wire" "$scratch/real"
printf '(lang dune 3.22)\n' > "$scratch/wire/dune-project"
printf '(library (name wire))\n' > "$scratch/wire/dune"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'case "$*" in' \
  '  "describe workspace --format csexp --lang 0.1 --root "*)' \
  '    root=${!#}' \
  '    printf "((4:root%d:%s)(13:build_context14:_build/default))" "${#root}" "$root" ;;' \
  '  "describe rules --recursive @@./check --root "*) cat "$RULES_FILE" ;;' \
  '  *) exit 91 ;;' \
  'esac' > "$scratch/bin/dune"
chmod +x "$scratch/bin/dune"
RULES_FILE="$PWD/quoted.sexp" PATH="$scratch/bin:$PATH" "$probe" built \
  "$scratch/wire/literal%{name}.ml" \
  "$scratch/wire/even\%{name}.ml" \
  "$scratch/wire/odd\%{name}.ml"
# Other invalid escapes, truncation and bad decimal escapes must still fail closed.
for payload in '\q' '\%x' '\999'; do
  printf '((deps ()) (targets ((files (x.cmt)))) (context default) (action "%s"))\n' \
    "$payload" > "$scratch/bad.sexp"
  RULES_FILE="$scratch/bad.sexp" PATH="$scratch/bin:$PATH" "$probe" unknown \
    "$scratch/wire/bad.ml"
done
printf '%s' '((deps ()) (action "unfinished' > "$scratch/bad.sexp"
RULES_FILE="$scratch/bad.sexp" PATH="$scratch/bin:$PATH" "$probe" unknown \
  "$scratch/wire/bad.ml"
# @@./check excludes descendant aliases; --recursive retains required compiler producers.
printf '(lang dune 3.22)\n' > "$scratch/real/dune-project"
printf '%s\n' '(test (name generated))' \
  '(rule (target generated.ml) (action (write-file %{target} "let () = ()")))' \
  '(rule (target generated.mli) (action (write-file %{target} "")))' > "$scratch/real/dune"
# Nested inspection uses a separate workspace, never the enclosing build lock.
env -u DUNE_INSIDE_DUNE "$probe" generated "$scratch/real"
# Literal data-only fixture Dune files are not compiler owners; the selected
# ordinary nested test still needs its exact compiler dependency closure.
mkdir "$scratch/real/tests" "$scratch/real/fixtures"
cp "$scratch/real/dune" "$scratch/real/tests/dune"
printf '(data_only_dirs fixtures)\n' > "$scratch/real/dune"
printf '(library (name ignored_fixture))\n' > "$scratch/real/fixtures/dune"
env -u DUNE_INSIDE_DUNE "$probe" generated "$scratch/real" tests
# ^safe-y047: a checkout can advance authored mtimes without changing compiler input.
mkdir -p "$scratch/plain/build"
printf 'let value = 1\n' > "$scratch/plain/value.ml"
printf 'val value : int\n' > "$scratch/plain/value.mli"
cp "$scratch/plain/value.ml" "$scratch/plain/value.mli" "$scratch/plain/build/"
(cd "$scratch/plain/build"; ocamlc -bin-annot -c value.mli; ocamlc -bin-annot -c value.ml)
touch -d '2030-01-01 UTC' "$scratch/plain/value.ml"
"$probe" checked "$scratch/plain/build/value.cmt" "$scratch/plain/value.ml"
printf 'let value = 2\n' > "$scratch/plain/value.ml"
touch -r "$scratch/plain/build/value.ml" "$scratch/plain/value.ml"
if "$probe" checked "$scratch/plain/build/value.cmt" "$scratch/plain/value.ml"; then
  echo 'changed source with preserved timestamp was accepted' >&2; exit 1
fi
cp "$scratch/plain/value.ml" "$scratch/plain/build/value.ml"
if "$probe" checked "$scratch/plain/build/value.cmt" "$scratch/plain/value.ml"; then
  echo 'changed compiler input was accepted' >&2; exit 1
fi
# Preprocessed input still requires its separate authored-source freshness safeguard.
cp "$scratch/plain/build/value.ml" "$scratch/plain/build/value.pp.ml"
(cd "$scratch/plain/build"; ocamlc -bin-annot -c -impl value.pp.ml -o value.cmo)
touch -d '2030-01-01 UTC' "$scratch/plain/value.ml"
if "$probe" checked "$scratch/plain/build/value.cmt" "$scratch/plain/value.ml"; then
  echo 'preprocessed source timestamp safeguard was lost' >&2; exit 1
fi
printf '%s\n' 'inventory: Dune escapes, malformed input, scoped compiler dependencies and content freshness: pass'
