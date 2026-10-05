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
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'case "$*" in' \
  '  "describe workspace --format csexp --lang 0.1 --root "*)' \
  '    root=${!#}' \
  '    printf "((4:root%d:%s)(13:build_context14:_build/default))" "${#root}" "$root" ;;' \
  '  "describe rules --recursive @check --root "*) cat "$RULES_FILE" ;;' \
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
# The actual command, including --recursive, must discover test compilation rules.
printf '(lang dune 3.22)\n' > "$scratch/real/dune-project"
printf '%s\n' '(test (name generated))' \
  '(rule (target generated.ml) (action (write-file %{target} "let () = ()")))' \
  '(rule (target generated.mli) (action (write-file %{target} "")))' > "$scratch/real/dune"
# Nested inspection uses a separate workspace, never the enclosing build lock.
env -u DUNE_INSIDE_DUNE "$probe" generated "$scratch/real"
printf '%s\n' 'inventory: Dune escapes, binary actions, malformed input and recursive rules: pass'
